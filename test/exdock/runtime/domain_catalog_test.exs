defmodule Exdock.Runtime.DomainCatalogTest do
  use ExUnit.Case, async: true

  alias Exdock.Runtime.{DomainCatalog, EventCatalog, Mutation, MutationContract}

  test "owns the runtime domain vocabulary" do
    assert DomainCatalog.domains() == Mutation.domains()
    assert DomainCatalog.cluster_domains() == [:nodes, :images, :containers]
    assert DomainCatalog.cluster_snapshot_domains() == [:nodes, :images, :containers, :repositories]
    assert DomainCatalog.valid?(:settings)
    refute DomainCatalog.valid?(:unknown)
  end

  test "associates mutation actions with their owning domains" do
    assert DomainCatalog.domains() == MutationContract.domains()
    assert DomainCatalog.actions(:images) == MutationContract.actions(:images)
    assert DomainCatalog.valid_action?(:settings, :user_setting)
    assert DomainCatalog.valid_action?(:containers, :set_resources)
    refute DomainCatalog.valid_action?(:settings, :set_resources)
    refute DomainCatalog.valid_action?(:unknown, :user_setting)
  end

  test "keeps payload validation behind the static mutation contract" do
    payload = {:single, "example/app:latest", "https://example.com/repository"}

    assert MutationContract.valid_payload?(:images, :repository_url, payload)
    refute MutationContract.valid_payload?(:settings, :repository_url, payload)
    refute MutationContract.valid_payload?(:images, :repository_url, {:single, :invalid, nil})
  end

  test "plans transitive reloads in domain order" do
    assert DomainCatalog.dependents(:settings, :all) == [:nodes, :images, :containers]
    assert DomainCatalog.dependents(:settings, :user_setting) == []
    assert DomainCatalog.dependents(:tags, :all) == [:containers]
    assert DomainCatalog.dependents(:images, :all) == [:containers]
  end

  test "maps changed domains to derived projection invalidations" do
    assert DomainCatalog.derived_projections([:nodes]) == [:cluster_info, :server_configuration]
    assert DomainCatalog.derived_projections([:settings]) == [:server_configuration]
    assert DomainCatalog.derived_projections([:repositories, :tags]) == []
  end

  test "every state and derived projection source has event routing" do
    emitted_sources =
      DomainCatalog.domains() ++ DomainCatalog.derived_projections(DomainCatalog.domains())

    assert Enum.all?(emitted_sources, &EventCatalog.known_source?/1)
    assert Enum.all?([:status, :log], &EventCatalog.known_source?/1)
  end
end
