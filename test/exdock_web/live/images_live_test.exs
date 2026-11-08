defmodule ExdockWeb.ImagesLiveTest do
  use ExdockWeb.LiveCase

  import Phoenix.LiveViewTest

  alias Exdock.ReadModel.Image
  alias ExdockWeb.ImagesLiveTest.ImagesListHarness

  describe "images live view" do
    test "renders the images page shell with actionable controls", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/images")

      assert has_element?(view, "#app-shell")
      assert has_element?(view, "#images-index")
      assert has_element?(view, "#images-live-page")
      assert has_element?(view, "aside")
      assert has_element?(view, "#images-node-refresh-button")
      assert has_element?(view, "#images-registries-button")
      assert has_element?(view, "#about-page")
      assert has_element?(view, "#settings-page")
    end

    test "renders seeded image row in its node modal", %{conn: conn} do
      %{node: node, image_id: image_id} = seed_image_row()

      {:ok, view, _html} = live(conn, ~p"/images")
      summary_id = ExdockWeb.PageLive.Utils.IdUtils.create_id("nodesummary#{node}")

      assert has_element?(view, "#images-live-page")
      assert has_element?(view, "##{summary_id}-header p", node)
      assert has_element?(view, "#sidebar-images-summary")
      assert has_element?(view, "#sidebar-images-summary", "Available for cleanup")

      modal_component_id = ExdockWeb.PageLive.Utils.IdUtils.create_id("nodeimagescomponent#{node}")
      images_list_id = ExdockWeb.PageLive.Utils.IdUtils.create_id("images_list#{modal_component_id}")
      cleanup_button_id = ExdockWeb.PageLive.Utils.IdUtils.create_id("delete-unused-images-#{node}")

      assert has_element?(view, "##{modal_component_id} td", image_id)
      assert has_element?(view, "##{images_list_id} table")
      assert has_element?(view, "##{cleanup_button_id}[phx-click='image_delete_unused']")
    end

    test "rebuilds cached image summaries when image broadcasts arrive", %{conn: conn} do
      %{node: node, image_id: image_id} = seed_image_row()
      {:ok, view, _html} = live(conn, ~p"/images")

      assert has_element?(view, "#sidebar-images-summary", "Available for cleanup")

      send(view.pid, {:images, %{node => []}})

      refute has_element?(view, "td", image_id)
    end

    test "refresh button triggers event handling without leaving the page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/images")

      view
      |> element("#images-node-refresh-button")
      |> render_click()

      assert has_element?(view, "#images-live-page")
    end

    test "image lock button persists delete protection for the selected image", %{conn: conn} do
      %{node: node, image_id: image_id} = seed_image_row()

      {:ok, view, _html} = live(conn, ~p"/images")
      subscribe_to_operations!()

      render_click(view, "image_delete_lock", %{
        "nodename" => node,
        "imageid" => image_id,
        "tolock" => "true"
      })

      assert %{status: :completed} = await_operation!(:set_image_delete_lock)
      assert image_lock?(node, image_id)

      assert has_element?(
               view,
               "button[phx-click='image_delete_lock'][phx-value-imageid='#{image_id}'][phx-value-tolock='false']"
             )

      view
      |> element("button[phx-click='image_delete_lock'][phx-value-imageid='#{image_id}'][phx-value-tolock='false']")
      |> render_click()

      assert %{status: :completed} = await_operation!(:set_image_delete_lock)
      refute image_lock?(node, image_id)
    end

    test "delete button sends the selected image payload through the page handler", %{conn: conn} do
      %{image_id: image_id} = seed_image_row()

      {:ok, view, _html} = live(conn, ~p"/images")

      view
      |> element("button[phx-click='image_delete'][phx-value-imageid='#{image_id}']")
      |> render_click()

      assert has_element?(view, "#images-live-page")
      refute has_element?(view, "#flash-error", "Invalid image delete request")
    end

    test "delete unused button queues the node-scoped image cleanup flow", %{conn: conn} do
      %{node: node} = seed_image_row()

      {:ok, view, _html} = live(conn, ~p"/images")

      render_click(view, "image_delete_unused", %{"node" => node})

      assert has_element?(view, "#images-live-page")
    end

    test "malformed image actions show an error without terminating the page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/images")

      render_click(view, "image_delete_lock", %{
        "nodename" => "unknown-node",
        "imageid" => "image-id",
        "tolock" => "sometimes"
      })

      assert has_element?(view, "#images-live-page")
      assert has_element?(view, "#flash-error", "Invalid image lock request")
    end

    test "image rows render delete and lock controls with node/image payloads", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, ImagesListHarness)

      assert has_element?(
               view,
               "button[phx-click='image_delete'][phx-value-nodename='images_node'][phx-value-imageid='img-harness']"
             )

      assert has_element?(
               view,
               "button[phx-click='image_delete_lock'][phx-value-nodename='images_node'][phx-value-imageid='img-harness'][phx-value-tolock='true']"
             )

      assert has_element?(view, "tr.images-list-row")
      assert has_element?(view, "button.image-lock-button")

      view
      |> element("button[phx-click='image_delete_lock'][phx-value-imageid='img-harness']")
      |> render_click()

      assert has_element?(view, "#last-images-list-event", "image_delete_lock:img-harness")

      view
      |> element("button[phx-click='image_delete'][phx-value-imageid='img-harness']")
      |> render_click()

      assert has_element?(view, "#last-images-list-event", "image_delete:img-harness")
    end
  end

  defp seed_image_row do
    node_id = "images_node_#{System.unique_integer([:positive])}"
    image_id = "img-#{System.unique_integer([:positive])}"
    image_tag = "v#{System.unique_integer([:positive])}"

    {:ok, _} =
      %Exdock.Database.Image.Record{
        node: node_id,
        id: image_id,
        name: "acme/fixture#{image_id}:#{image_tag}",
        tags: [image_tag],
        digest: "sha256:#{String.duplicate("a", 16)}",
        size: 64_000_000,
        shared_size: 1_024,
        build_date: ~U[2026-01-01 00:00:00Z]
      }
      |> Exdock.Database.Image.insert()

    :ok =
      Exdock.Runtime.Coordinator.node_is_up(node_id, %{"platform" => "linux/amd64"})

    assert snapshot_contains?(node_id, image_id)

    %{node: node_id, image_id: image_id, image_tag: image_tag}
  end

  defp snapshot_contains?(node_id, image_id) do
    Exdock.ReadModel.page([:images]).images
    |> Map.get(node_id, [])
    |> Enum.any?(fn
      %Image{id: ^image_id} -> true
      _ -> false
    end)
  end

  defp image_lock?(node_id, image_id) do
    Exdock.ReadModel.page([:images]).images
    |> Map.get(node_id, [])
    |> Enum.find(fn
      %Image{id: ^image_id} -> true
      _ -> false
    end)
    |> case do
      %Image{settings: %{delete_lock: lock}} -> lock
      _ -> nil
    end
  end
end
