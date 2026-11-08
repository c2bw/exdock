defmodule ExdockWeb.HomepagePresentationTest do
  use ExUnit.Case, async: true

  alias ExdockWeb.HomepageLive.Presentation

  test "keeps node rows sorted when the cluster projection changes" do
    presentation = Presentation.build(%{by_node_string: %{"node-b" => %{id: 2}}}, %{})

    updated =
      Presentation.with_cluster_info(
        presentation,
        %{by_node_string: %{"node-b" => %{id: 2}, "node-a" => %{id: 1}}}
      )

    assert updated.node_rows == [{"node-a", %{id: 1}}, {"node-b", %{id: 2}}]
    assert updated.resource_rows == presentation.resource_rows
  end

  test "container projection changes preserve cached node rows" do
    presentation = Presentation.build(%{by_node_string: %{"node-a" => %{id: 1}}}, %{})
    updated = Presentation.with_containers(presentation, %{"node-a" => %{}})

    assert updated.node_rows == presentation.node_rows
    assert Map.has_key?(updated.resource_rows, "node-a")
  end
end
