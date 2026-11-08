defmodule ExdockWeb.PageLive.PageUtilitiesTest do
  use ExUnit.Case, async: true

  alias ExdockWeb.PageLive.Utils.EventParams
  alias ExdockWeb.PageLive.Utils.{ModalState, SettingsTextParser, URLParam}

  test "URL-safe repository values round-trip" do
    repository = "https://github.com/example/project"

    assert {:ok, ^repository} = repository |> URLParam.encode() |> URLParam.decode()
  end

  test "malformed URL-safe repository values are invalid" do
    assert {:invalid, ""} = URLParam.decode("%%%")
  end

  test "modal state checks keys directly" do
    assert ModalState.render?(%{"settings" => true}, "settings")
    refute ModalState.render?(%{"settings" => true}, "log")
  end

  test "priority parameters are parsed without raising and constrained to the supported range" do
    assert {:ok, 3} = EventParams.priority("3")
    assert {:error, :invalid_priority} = EventParams.priority("three")
    assert {:error, :invalid_priority} = EventParams.priority("6")
    assert {:error, :invalid_priority} = EventParams.priority(nil)
  end

  test "boolean parameters accept only explicit boolean values" do
    assert {:ok, true} = EventParams.boolean("true")
    assert {:ok, false} = EventParams.boolean(false)
    assert {:error, :invalid_boolean} = EventParams.boolean("enabled")
  end

  test "structured image and container jobs reject missing and empty values" do
    assert {:ok, [%{node: "node-a", image_tag: "repo/api:latest"}]} =
             EventParams.image_jobs(%{
               "images" => [%{"node" => "node-a", "image_tag" => "repo/api:latest"}]
             })

    assert {:ok, [{"node-a", "api"}]} =
             EventParams.container_jobs(%{
               "containers" => [%{"node" => "node-a", "name" => "api"}]
             })

    assert {:error, :invalid_image_jobs} = EventParams.image_jobs(%{"images" => []})
    assert {:error, :invalid_image_jobs} = EventParams.image_jobs(%{"node" => "node-a"})

    assert {:error, :invalid_container_jobs} =
             EventParams.container_jobs(%{
               "containers" => [%{"node" => "node-a", "name" => ""}]
             })
  end

  test "image and repository action parameters share strict decoding" do
    assert {:ok, {"node-a", "sha256:image"}} =
             EventParams.image_delete(%{"nodename" => "node-a", "imageid" => "sha256:image"})

    assert {:ok, "node-a"} = EventParams.image_cleanup(%{"node" => "node-a"})

    assert {:ok, {"node-a", "sha256:image", true}} =
             EventParams.image_lock(%{
               "nodename" => "node-a",
               "imageid" => "sha256:image",
               "tolock" => "true"
             })

    assert {:ok, "https://github.com/example/app"} =
             EventParams.repository(%{"repository" => "https://github.com/example/app"})

    assert {:error, :invalid_image_delete} =
             EventParams.image_delete(%{"nodename" => "node-a", "imageid" => " "})

    assert {:error, :invalid_image_lock} =
             EventParams.image_lock(%{
               "nodename" => "node-a",
               "imageid" => "image",
               "tolock" => "sometimes"
             })

    assert {:error, :invalid_repository} = EventParams.repository(%{"repository" => ""})
  end

  test "repository overrides reject partially malformed input" do
    assert {:ok, [{"app:latest", "https://github.com/example/app"}]} =
             SettingsTextParser.repository_overrides("app:latest -> https://github.com/example/app")

    assert {:error, :invalid_repository_overrides} =
             SettingsTextParser.repository_overrides("""
             malformed
             app:latest -> https://github.com/example/app
             """)

    assert {:error, :invalid_repository_overrides} =
             SettingsTextParser.repository_overrides([])
  end

  test "container priorities reject partially malformed input" do
    assert {:ok, [{"node-a", "api", 4}, {"node-b", "worker", 2}]} =
             SettingsTextParser.container_priorities("""
             node-a -> api -> 4
             node-b -> worker -> 2
             """)

    assert {:error, :invalid_container_priorities} =
             SettingsTextParser.container_priorities("""
             node-a -> api -> 4
             node-b -> worker -> invalid
             """)

    assert {:error, :invalid_container_priorities} =
             SettingsTextParser.container_priorities([{"node-a", "api", 6}])
  end
end
