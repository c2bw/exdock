defmodule Exdock.Server.State.JobsTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.State.Jobs
  alias Exdock.Runtime.Command.Workflow
  alias Exdock.Server.Jobs.{Detail, Plan, Spec, Submission}
  alias Exdock.Server.Jobs.Spec.Local
  alias Exdock.Server.State
  alias Exdock.Server.State.Storage

  describe "compose/1" do
    test "builds the expected registry update chain" do
      assert %Workflow{step: :node_refresh, remaining: [:registry_fetch]} =
               Jobs.compose(:registry_update)
    end

    test "builds the expected container update chain" do
      assert %Workflow{
               step: :node_refresh,
               remaining: [:registry_fetch, :containers_update]
             } =
               Jobs.compose(:containers_update)
    end
  end

  describe "job plans" do
    test "preserves empty work" do
      assert Plan.new(nil) |> Plan.empty?()
      assert Plan.new([]) |> Plan.empty?()
      assert :empty = Plan.new(nil) |> Plan.attach_operation("operation-id") |> Plan.submission()
    end

    test "rekeys one detail and all of its executable specs" do
      detail = Detail.new(:refresh, [spec(:one), spec(:two)])
      operation_id = Ecto.UUID.generate()

      assert {:one, attached} =
               detail
               |> Plan.new()
               |> Plan.attach_operation(operation_id)
               |> Plan.submission()

      assert attached.id == operation_id
      assert Enum.all?(attached.spec_list, fn {_spec, id} -> String.starts_with?(id, operation_id) end)
    end

    test "uses the operation id to package multiple independent details" do
      first = detail(:first)
      second = detail(:second)
      operation_id = Ecto.UUID.generate()

      assert {:one, %Exdock.Server.Jobs.Package{id: ^operation_id, name: :first, details: details}} =
               [first, second]
               |> Plan.new()
               |> Plan.attach_operation(operation_id)
               |> Plan.submission()

      assert length(details) == 2
    end

    test "marks every independent detail as automated" do
      assert {:individual, details} =
               [detail(:first), detail(:second)]
               |> Plan.new()
               |> Plan.automated(true)
               |> Plan.submission()

      assert Enum.all?(details, & &1.is_automated)
    end

    test "preserves batch submission for non-automated independent details" do
      details = [detail(:first), detail(:second)]
      assert {:batch, ^details} = details |> Plan.new() |> Plan.submission()
    end

    test "submits an empty plan without contacting the dispatcher" do
      assert :ok = nil |> Plan.new() |> Submission.submit()
    end
  end

  describe "build/2" do
    test "normalizes empty workflow steps into empty plans" do
      cluster = Storage.Cluster.new()

      assert %Plan{} =
               node_plan =
               Jobs.build(%State{cluster: cluster}, Workflow.new(:node_refresh, []))

      assert Plan.empty?(node_plan)

      assert %Plan{} =
               registry_plan =
               Jobs.build(
                 %State{cluster: cluster, tags: %Storage.TagsInfo{tags: %{}}},
                 Workflow.new(:registry_fetch, [])
               )

      assert Plan.empty?(registry_plan)
    end
  end

  test "workflow container updates keep automation metadata through submission" do
    alias Exdock.Server.State.ClientMessagesFixtures, as: Fixtures
    alias Exdock.Runtime.Command.Execution
    state = Fixtures.state_with_container()
    [container] = Storage.Containers.list_node(state.cluster.storage, "node")

    container = %{
      container
      | core: %{
          container.core
          | image_data: %{container.core.image_data | status: :outdated},
            settings: %{container.core.settings | auto_update: :enabled}
        }
    }

    user = Exdock.Domain.UserSettings.default()
    state = %{state | settings: %Storage.Settings{user: %{user.user => user}}}

    for containers <- [[container], [container, %{container | name: "worker", id: "worker-id"}]] do
      storage = Storage.Containers.set_node(state.cluster.storage, "node", containers)
      state = %{state | cluster: %{state.cluster | storage: storage}}
      workflow = Workflow.new(:containers_update, [])
      plan = Jobs.build(state, workflow)
      assert {^state, [{:submit_plan, submitted}]} = Execution.resolve(state, {:work, plan}, nil, workflow, [])
      assert submitted.automated?

      details =
        case Plan.submission(submitted) do
          {:individual, details} -> details
          {:one, %Exdock.Server.Jobs.Package{details: details}} -> details
        end

      assert length(details) == length(containers) * 2
      assert Enum.all?(details, & &1.is_automated)
      assert Enum.map(details, & &1.name) == List.flatten(List.duplicate([:image_pull, :container_recreate], length(containers)))
    end
  end

  defp detail(name), do: Detail.new(name, spec(name))
  defp spec(data), do: Spec.new(Local.new(fn _job_id -> :ok end), [], data)
end
