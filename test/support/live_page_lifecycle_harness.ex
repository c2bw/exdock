defmodule ExdockWeb.LivePageTest.LifecycleHarness do
  @moduledoc false

  use ExdockWeb, :live_view

  use ExdockWeb.PageLive.LivePage.Use,
    title: "Lifecycle probe",
    load: [:nodes, :containers, :repositories, :cluster_info]

  def handle_page_broadcast({:page_probe, value}, socket),
    do: Phoenix.Component.assign(socket, :page_probe, value)

  def handle_page_broadcast(_message, _socket), do: :unhandled

  def render(%{page: page} = assigns) when page in ["loading", "error"] do
    ~H"""
    <div id={"lifecycle-#{@page}"}>{@page}</div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="lifecycle-harness">
      <p id="lifecycle-title">{@page_title}</p>
      <p id="lifecycle-node-count">{map_size(@nodes)}</p>
      <p id="lifecycle-container-count">{map_size(@containers)}</p>
      <p id="lifecycle-status">{inspect(@status)}</p>
      <p id="lifecycle-page-probe">{assigns[:page_probe]}</p>
      <p id="lifecycle-images-loaded">{Map.has_key?(assigns, :images)}</p>
    </div>
    """
  end
end
