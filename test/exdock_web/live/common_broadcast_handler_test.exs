defmodule ExdockWeb.CommonBroadcastHandlerTest do
  use ExdockWeb.LiveCase

  alias Exdock.Server.State.Storage.Persistence.Node, as: NodePersistence
  alias Exdock.Domain
  alias ExdockWeb.PageLive.Utils.CommonBroadcastHandler

  describe "common broadcast handler helpers" do
    test "accepts canonical string-keyed node maps" do
      node = "broadcast-node-#{System.unique_integer([:positive])}"

      :ok =
        node
        |> Domain.Node.default()
        |> NodePersistence.insert()

      normalized =
        CommonBroadcastHandler.node_map!(%{
          node => :known,
          "external-node-name" => :unknown
        })

      assert Map.fetch!(normalized, node) == :known
      assert Map.fetch!(normalized, "external-node-name") == :unknown
    end
  end
end
