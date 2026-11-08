defmodule ExdockWeb.ImagesLive.PresentationTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias ExdockWeb.ImagesLive.Presentation

  test "untagged images retain a visible label and deletion control" do
    image = %{
      tags: [],
      id: "sha256:" <> String.duplicate("a", 64),
      size: 1024,
      shared_size: 0,
      size_human: "1 KB",
      build_date: ~U[2026-01-01 00:00:00Z],
      in_use: false,
      settings: %{delete_lock: false}
    }

    document =
      render_component(
        &ExdockWeb.ImagesLive.ImagesList.render/1,
        %{id: "untagged-images", nodename: "node", images: [{"untagged-row", %{image: image}}]}
      )
      |> LazyHTML.from_fragment()

    assert Enum.count(LazyHTML.query(document, "#untagged-row span[title='untagged']")) == 1
    assert Enum.count(LazyHTML.query(document, "#untagged-row-delete[aria-label='Delete image untagged']")) == 1
    assert %{registries: [{"Local image", 1}]} = Presentation.build([Map.put(image, :name, image.id)])
  end

  test "builds inventory counts and stable registry rows in one pass" do
    images = [
      %{name: "ghcr.io/acme/api:v1", in_use: true, settings: %{delete_lock: false}},
      %{name: "ghcr.io/acme/web:v1", in_use: false, settings: %{delete_lock: false}},
      %{name: "docker.io/acme/db:v1", in_use: false, settings: %{delete_lock: true}}
    ]

    assert %{
             summary: %{total: 3, used: 1, unused: 1, locked: 1},
             registries: [{"GitHub", 2}, {"Docker Hub", 1}]
           } = Presentation.build(images)
  end

  test "treats absent usage and lock data as false" do
    assert %{summary: %{total: 1, used: 0, unused: 1, locked: 0}} =
             Presentation.build([%{name: "acme/api:v1"}])
  end

  test "sorts node rows at the cluster projection boundary" do
    cluster_info = %{by_node_string: %{"node-b" => %{id: 2}, "node-a" => %{id: 1}}}

    assert Presentation.node_rows(cluster_info) == [
             {"node-a", %{id: 1}},
             {"node-b", %{id: 2}}
           ]
  end
end
