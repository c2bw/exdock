defmodule ExdockWeb.ImagesLiveTest.ImagesListHarness do
  @moduledoc false

  use ExdockWeb, :live_view

  alias Exdock.Domain.Image
  alias Exdock.Domain.Image.Settings

  @impl true
  def mount(_params, _session, socket) do
    image = image_fixture("img-harness")

    {:ok,
     socket
     |> Phoenix.Component.assign(last_event: "")
     |> Phoenix.LiveView.stream(:images, [%{id: "img-harness", image: image}])}
  end

  @impl true
  def handle_event(event, params, socket) do
    image_id = params["imageid"] || params["node"] || "submit"
    {:noreply, Phoenix.Component.assign(socket, :last_event, "#{event}:#{image_id}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="images-list-harness">
      <ExdockWeb.ImagesLive.ImagesList.render
        id="images-list"
        nodename="images_node"
        images={@streams.images}
      />
      <p id="last-images-list-event">{@last_event}</p>
    </div>
    """
  end

  defp image_fixture(image_id) do
    %Image{
      id: image_id,
      tags: ["repo/harness:latest"],
      size: 64_000,
      shared_size: 1_000,
      size_human: "64 kB",
      build_date: ~U[2026-01-01 00:00:00Z],
      in_use: false,
      settings: %Settings{delete_lock: false}
    }
  end
end
