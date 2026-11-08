defmodule Exdock.Database.ImageSettingsTest do
  use Exdock.DataCase, async: false

  alias Exdock.Database.ImageSettings
  alias Exdock.Domain.Image.Settings

  test "round-trips node names through database strings" do
    settings = %Settings{delete_lock: true}

    assert {:ok, %ImageSettings{node: "node_a", id: "sha256:image-id", delete_lock: true}} =
             settings
             |> persisted_settings("node_a", "sha256:image-id")
             |> ImageSettings.insert()

    assert %ImageSettings{node: "node_a", id: "sha256:image-id", delete_lock: true} =
             ImageSettings.load("node_a", "sha256:image-id")
  end

  test "load/2 accepts validated string node keys" do
    assert {:ok, %ImageSettings{}} =
             %Settings{delete_lock: true}
             |> persisted_settings("node_a", "sha256:image-id")
             |> ImageSettings.insert()

    assert %ImageSettings{node: "node_a", id: "sha256:image-id", delete_lock: true} =
             ImageSettings.load("node_a", "sha256:image-id")
  end

  test "load_all/0 returns runtime node names" do
    assert {:ok, %ImageSettings{}} =
             %Settings{delete_lock: true}
             |> persisted_settings("node_a", "sha256:image-a")
             |> ImageSettings.insert()

    assert {:ok, %ImageSettings{}} =
             %Settings{delete_lock: false}
             |> persisted_settings("node_b", "sha256:image-b")
             |> ImageSettings.insert()

    assert [
             %ImageSettings{node: "node_a", id: "sha256:image-a", delete_lock: true},
             %ImageSettings{node: "node_b", id: "sha256:image-b", delete_lock: false}
           ] = Enum.sort_by(ImageSettings.load_all(), & &1.id)
  end

  test "insert/1 upserts image settings by node and id" do
    assert {:ok, %ImageSettings{}} =
             %Settings{delete_lock: true}
             |> persisted_settings("node_a", "sha256:image-id")
             |> ImageSettings.insert()

    assert {:ok, %ImageSettings{node: "node_a", id: "sha256:image-id", delete_lock: false}} =
             %Settings{delete_lock: false}
             |> persisted_settings("node_a", "sha256:image-id")
             |> ImageSettings.insert()

    assert [%ImageSettings{node: "node_a", id: "sha256:image-id", delete_lock: false}] =
             ImageSettings.load_all()
  end

  defp persisted_settings(%Settings{} = settings, node, id) do
    settings
    |> Map.from_struct()
    |> Map.merge(%{node: node, id: id})
    |> ImageSettings.new()
  end
end
