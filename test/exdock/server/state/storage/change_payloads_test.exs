defmodule Exdock.Server.State.Storage.MutationsTest do
  use ExUnit.Case, async: true

  alias Exdock.Runtime.Mutation
  alias Exdock.Server.State.Storage
  alias Exdock.Domain.Container

  describe "nested change helpers" do
    test "target the storage modules that implement change/2" do
      resources = %Container.Resources.Record{}

      assert %Mutation{domain: :repositories} = Storage.Repositories.Change.releases([])
      assert %Mutation{domain: :tags} = Storage.TagsInfo.Change.tags([])
      assert %Mutation{domain: :settings} = Storage.Settings.Change.cron("0 22 * * *")
      assert %Mutation{domain: :containers} = Storage.Containers.Change.resources("node", "id", resources)

      assert %Mutation{domain: :containers} =
               Storage.Containers.Change.logs("node", "id", [], ~U[2026-07-31 12:00:00Z])
    end
  end
end
