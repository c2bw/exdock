defmodule Exdock.Server.Jobs.CatalogTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Jobs.Catalog

  test "routes authenticated remote result families from one catalog" do
    assert Catalog.client_result_handler(:node_refresh) == :node_refresh
    assert Catalog.client_result_handler(:container_logs) == :container
    assert Catalog.client_result_handler(:registry_fetch) == nil
    assert Catalog.client_result_handler(:unknown) == nil
  end

  test "describes duplicate-work and failure-message policies" do
    assert Catalog.linkable_remote_mutation?(:container_restart)
    assert Catalog.linkable_remote_mutation?(:image_pull)
    refute Catalog.linkable_remote_mutation?(:container_logs)
    refute Catalog.linkable_remote_mutation?(:unknown)

    assert Catalog.failure_verb!(:container_stop) == "stopping container"
    assert :container_stop in Catalog.container_mutation_names()
  end
end
