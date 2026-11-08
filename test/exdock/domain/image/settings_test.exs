defmodule Exdock.Domain.Image.SettingsTest do
  use Exdock.DataCase, async: false

  alias Exdock.Database
  alias Exdock.Server.State.Storage.Persistence.ImageSettings, as: ImageSettingsPersistence
  alias Exdock.Domain.Image.Settings

  test "insert/3 stores and load/2 returns image settings structures" do
    settings = %Settings{delete_lock: true}

    assert {:ok, %Database.ImageSettings{node: "node_a", id: "sha256:image-id", delete_lock: true}} =
             ImageSettingsPersistence.insert(settings, "node_a", "sha256:image-id")

    assert %Settings{delete_lock: true} = ImageSettingsPersistence.load("node_a", "sha256:image-id")
  end

  test "load/2 accepts string node keys" do
    assert {:ok, _stored} =
             ImageSettingsPersistence.insert(%Settings{delete_lock: true}, "node_a", "sha256:image-id")

    assert %Settings{delete_lock: true} = ImageSettingsPersistence.load("node_a", "sha256:image-id")
  end

  test "import/3 applies valid fields and falls back to defaults for invalid values" do
    assert {:ok, %Database.ImageSettings{delete_lock: true}} =
             ImageSettingsPersistence.import(%{"delete_lock" => true}, "node_a", "sha256:locked")

    assert {:ok, %Database.ImageSettings{delete_lock: false}} =
             ImageSettingsPersistence.import(%{"delete_lock" => "yes"}, "node_a", "sha256:default")
  end
end
