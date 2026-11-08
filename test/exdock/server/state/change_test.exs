defmodule Exdock.Server.State.ChangeTest do
  use ExUnit.Case, async: true

  alias Exdock.Runtime.Mutation
  alias Exdock.Runtime.DomainCatalog
  alias Exdock.Server.State
  alias Exdock.Server.State.{Change, Domain}
  alias Exdock.Server.State.Change.{Operation, Outcome, Plan}
  alias Exdock.Server.State.Storage

  test "change coordination is stateless" do
    assert :stateless = Change.new()
  end

  test "domain registry exposes transitive dependents in reload order" do
    assert Domain.dependents(:settings, :all) == [:nodes, :images, :containers]
    assert Domain.dependents(:settings, :user_setting) == []
    assert Domain.dependents(:tags, :all) == [:containers]
    assert Domain.dependents(:repositories, :all) == []
    assert Domain.dependents(:nodes, :all) == []
    assert Domain.dependents(:images, :all) == [:containers]
    assert Domain.dependents(:containers, :all) == []
  end

  test "persisted plans do not execute while reducers are being prepared" do
    owner = self()

    state = %State{}
    mutation = %Mutation{domain: :settings, action: :probe, data: owner}
    plan = Plan.persisted(Exdock.Server.State.ChangeProbe, state, mutation)

    assert %Operation{
             executor: Exdock.Server.State.ChangeProbe,
             state: ^state,
             mutation: ^mutation
           } = plan.operation

    assert Plan.reduce(plan) == {:error, :persistence_execution_required}
    refute_received :persisted

    assert %Outcome{state: ^state, broadcast_opts: [], effects: []} = Plan.execute(plan)
    assert_received :persisted
  end

  test "commit reports a rejected mutation and preserves state" do
    state = %State{revision: 4, cluster: Storage.Cluster.new()}
    assert {:ok, mutation} = Mutation.node_setting("missing-node", :web_ui, "value")

    assert {:error, {:node_setting_persistence, :node_not_found}, ^state} =
             Change.commit(state, mutation)
  end

  test "commit rejects unsupported domain actions without crashing" do
    state = %State{revision: 4, cluster: Storage.Cluster.new()}
    mutation = %Mutation{domain: :settings, action: :delete_lock, data: nil}

    assert {:error, {:unknown_state_action, :settings, :delete_lock}, ^state} =
             Change.commit(state, mutation)
  end

  test "commit rejects malformed payloads for every supported action without crashing" do
    state = %State{revision: 4, cluster: Storage.Cluster.new()}

    for domain <- DomainCatalog.domains(), action <- DomainCatalog.actions(domain) do
      mutation = %Mutation{domain: domain, action: action, data: nil}

      assert {:error, {:invalid_mutation_payload, ^domain, ^action}, ^state} =
               Change.commit(state, mutation)
    end
  end

  test "commit enforces the canonical contract for directly constructed mutation payloads" do
    state = %State{revision: 4, cluster: Storage.Cluster.new()}

    invalid_mutations = [
      %Mutation{domain: :containers, action: :auto_update, data: {"node", "app", :unexpected}},
      %Mutation{domain: :containers, action: :priority, data: [{"node", "app", "high"}]},
      %Mutation{domain: :images, action: :repository_url, data: {:list, [{"app", nil}]}}
    ]

    for %Mutation{domain: domain, action: action} = mutation <- invalid_mutations do
      assert {:error, {:invalid_mutation_payload, ^domain, ^action}, ^state} =
               Change.commit(state, mutation)
    end
  end

  test "commit applies the canonical payload contract before domain dispatch" do
    state = %State{revision: 4, cluster: Storage.Cluster.new()}

    malformed = [
      %Mutation{domain: :containers, action: :auto_update, data: {"node", "app", :unexpected}},
      %Mutation{domain: :images, action: :repository_url, data: {:list, [{"image", nil}]}},
      %Mutation{domain: :tags, action: :tags_info, data: [%{}]}
    ]

    for %Mutation{domain: domain, action: action} = mutation <- malformed do
      assert {:error, {:invalid_mutation_payload, ^domain, ^action}, ^state} =
               Change.commit(state, mutation)
    end
  end
end
