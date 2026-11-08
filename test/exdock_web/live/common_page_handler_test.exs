defmodule ExdockWeb.CommonPageHandlerTest do
  use ExdockWeb.LiveCase

  import Phoenix.LiveViewTest

  alias Exdock.Server.State.Storage.Persistence.ImageMetadata
  alias Exdock.Domain.Image.Metadata
  alias ExdockWeb.CommonPageHandlerTest.HandlerHarness

  describe "common page handler" do
    test "tracks lazy modal rendering", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, HandlerHarness)

      view
      |> element("#show-settings-modal")
      |> render_click()

      assert has_element?(view, "#settings-modal-rendered", "true")
      assert has_element?(view, "#active-modal-id", "settings-page")

      render_click(view, "hide_lazy_modal", %{"modal_id" => "settings-page"})

      assert has_element?(view, "#settings-modal-rendered", "false")
      assert has_element?(view, "#active-modal-id", "")
    end

    test "invalid configuration import surfaces a flash error", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, HandlerHarness)

      view
      |> element("#bad-config-import")
      |> render_click()

      assert has_element?(view, "#flash-error", "Configuration import: Jason Decode Error")
    end

    test "valid configuration import reaches the operation layer", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, HandlerHarness)
      subscribe_to_operations!()

      render_click(view, "import_server_configuration", %{
        "server_configuration" => Exdock.Configuration.to_json(Exdock.ReadModel.page([]).server_configuration)
      })

      assert %{status: :completed} = await_operation!(:import_server_configuration)
      refute has_element?(view, "#flash-error")
    end

    test "rendering statistics toggle updates UI state and persists the setting", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, HandlerHarness)
      subscribe_to_operations!()

      view
      |> element("#enable-rendering-statistics")
      |> render_click()

      assert has_element?(view, "#rendering-statistics-enabled", "true")
      assert %{status: :completed} = await_operation!(:change_user_setting)
    end

    test "container lifecycle events reach their canonical operations", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, HandlerHarness)
      subscribe_to_operations!()

      for {event, operation} <- [
            {"container-start", :start_container},
            {"container-stop", :stop_container},
            {"container-restart", :restart_container}
          ] do
        render_click(view, event, %{"node" => "node_a", "container_name" => "api"})
        assert %{status: :noop} = await_operation!(operation)
      end
    end

    test "repository URL and clear-errors events reach their operations", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, HandlerHarness)
      subscribe_to_operations!()

      render_click(view, "repository-url-update", %{
        "img_name" => "repo/api:latest",
        "new_url" => "https://github.com/example/api"
      })

      assert %{status: :completed} = await_operation!(:set_image_repository_url)

      render_click(view, "clear_errors", %{})
      assert %{status: :completed} = await_operation!(:clear_errors)
    end

    test "ordinary operation rejection keeps the LiveView mounted and surfaces an error", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, HandlerHarness)

      view
      |> element("#reject-operation")
      |> render_click()

      assert has_element?(view, "#common-page-handler-harness")
      assert has_element?(view, "#flash-error", "Operation could not be accepted")
    end

    test "malformed structured event data is rejected without terminating the LiveView", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, HandlerHarness)

      render_click(view, "image-pull", %{"images" => [%{"node" => "node", "image_tag" => ""}]})

      assert has_element?(view, "#common-page-handler-harness")
      assert has_element?(view, "#flash-error", "Invalid image pull request")

      render_click(view, "container-recreate", %{
        "containers" => [%{"node" => "node", "name" => "api"}],
        "image_pull" => "perhaps"
      })

      assert has_element?(view, "#common-page-handler-harness")
      assert has_element?(view, "#flash-error", "Invalid container recreate request")
    end

    test "repository override import persists pasted image-to-repository mappings", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, HandlerHarness)

      image_name = "repo/imported-#{System.unique_integer([:positive])}:latest"
      repository_url = "https://github.com/example/imported"
      subscribe_to_operations!()

      render_click(view, "import_repository_overrides", %{
        "repositories_input" => """
        #{image_name} -> #{repository_url}
        """
      })

      assert %{status: :completed} = await_operation!(:set_image_repository_urls)
      assert %Metadata{repository_url: ^repository_url} = ImageMetadata.load(image_name)
    end

    test "repository override import rejects a partially malformed paste", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, HandlerHarness)

      image_name = "repo/rejected-#{System.unique_integer([:positive])}:latest"

      render_click(view, "import_repository_overrides", %{
        "repositories_input" => """
        malformed line
        #{image_name} -> https://github.com/example/rejected
        """
      })

      assert has_element?(view, "#flash-error", "Invalid repository overrides")
      assert ImageMetadata.load(image_name) == nil
    end
  end
end
