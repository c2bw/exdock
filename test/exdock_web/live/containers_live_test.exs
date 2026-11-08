defmodule ExdockWeb.ContainersLiveTest do
  use ExdockWeb.LiveCase

  import ExdockWeb.ContainersLiveFixtures
  import Phoenix.LiveViewTest

  alias ExdockWeb.PageLive.Utils.{IdUtils, URLParam}

  setup do
    unless Process.whereis(Exdock.Database.Vault) do
      start_supervised!({Exdock.Database.Vault, name: Exdock.Database.Vault})
    end

    :ok
  end

  test "renders containers page shell with expected surface ids", %{conn: conn} do
    %{node: node} = seed_node_with_containers()
    {:ok, view, _html} = live(conn, ~p"/containers/#{URLParam.encode(node)}")

    assert has_element?(view, "#app-shell")
    assert has_element?(view, "#containers-index")
    assert has_element?(view, "aside")
    assert has_element?(view, "[id$='-hardware-usage']")
    assert has_element?(view, "[id$='-hardware-usage']", "Hardware Usage")
    assert has_element?(view, "[id$='-hardware-usage']", "CPU")
    assert has_element?(view, "[id$='-hardware-usage']", "RAM")
    assert has_element?(view, "[id$='-hardware-usage']", "I/O")
    assert has_element?(view, "[id$='-hardware-usage']", "NET")
    assert has_element?(view, "[id$='-hardware-usage-platform']", "linux/amd64")
    refute has_element?(view, "[id$='-hardware-usage']", "Live")
    assert has_element?(view, "[id$='-hardware-usage']", "Total unavailable")
    assert has_element?(view, "#containers-registry-fetch-button")
    assert has_element?(view, "#containers-node-refresh-button")
    assert has_element?(view, "#about-page")
    assert has_element?(view, "#settings-page")
  end

  test "renders updated and outdated containers into dedicated tables", %{conn: conn} do
    %{node: node, updated_container: updated, outdated_container: outdated} =
      seed_node_with_containers()

    {:ok, view, _html} = live(conn, ~p"/containers/#{URLParam.encode(node)}")

    assert has_element?(view, "#containers-index")
    assert has_element?(view, "#not_runningcontainers_list_component")
    assert has_element?(view, "#not_runningcontainers_list_component", updated.name)
    assert has_element?(view, "#not_runningcontainers_list_component", outdated.name)
  end

  test "applies string-keyed container refreshes to rows and an open manager modal", %{
    conn: conn
  } do
    %{node: node, outdated_container: outdated} =
      seed_node_with_containers(running?: true)

    {:ok, view, _html} = live(conn, ~p"/containers/#{URLParam.encode(node)}")

    view
    |> element("#outdatedcontainers_list_component tr", outdated.name)
    |> render_click()

    modal_id = IdUtils.container_manager_id(node, outdated.name)
    assert has_element?(view, "##{modal_id}", "has not")

    node_key = to_string(node)
    containers = Exdock.ReadModel.page([:containers]).containers |> Map.fetch!(node_key)

    containers_with_latest_image =
      Enum.map(containers, fn
        %{name: name} = container when name == outdated.name ->
          mark_latest_image_present(container)

        container ->
          container
      end)

    send(view.pid, {:containers, %{node_key => containers_with_latest_image}})

    document = view |> render() |> LazyHTML.from_fragment()

    assert LazyHTML.filter(document, "##{modal_id} span.hero-check-circle.text-success-icon") != []

    assert LazyHTML.filter(
             document,
             "#outdatedcontainers_list_component span.hero-check-circle.text-success-icon"
           ) != []
  end

  test "redirects stale node routes back to homepage", %{conn: conn} do
    encoded_node = URLParam.encode("missing-node-#{System.unique_integer([:positive])}")

    assert {:error, {:live_redirect, %{to: "/"}}} =
             live(conn, ~p"/containers/#{encoded_node}")
  end

  test "redirects when the selected node disappears from a nodes broadcast", %{conn: conn} do
    %{node: node} = seed_node_with_containers()
    {:ok, view, _html} = live(conn, ~p"/containers/#{URLParam.encode(node)}")

    send(view.pid, {:nodes, %{}})

    assert_redirect(view, "/")
  end

  test "dispatches shell actions without leaving containers page", %{conn: conn} do
    %{node: node} = seed_node_with_containers()
    {:ok, view, _html} = live(conn, ~p"/containers/#{URLParam.encode(node)}")

    view |> element("#containers-node-refresh-button") |> render_click()
    assert has_element?(view, "#containers-index")

    view |> element("#containers-registry-fetch-button") |> render_click()
    assert has_element?(view, "#containers-index")
  end
end
