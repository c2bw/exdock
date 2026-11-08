defmodule Exdock.Server.Logging.Status.DashboardTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Logging.Status.{Dashboard, Lifecycle}

  @now ~U[2026-07-31 10:00:00Z]

  test "refresh rekeys a row without leaving the stale projection behind" do
    incoming = %{image_tag: "acme/app:latest"}
    stored = %{image_tag: "docker.io/acme/app:latest"}

    dashboard =
      Dashboard.new()
      |> Dashboard.add(
        Lifecycle.started(:image_pull, "job-1", [:node_a], incoming, @now),
        {:ok, :requested},
        incoming
      )
      |> Dashboard.refresh(
        Lifecycle.updated(:image_pull, "job-1", :node_a, incoming, nil, @now),
        stored
      )

    refute Map.has_key?(dashboard.image_pull, {:node_a, incoming})
    assert Map.has_key?(dashboard.image_pull, {:node_a, stored})
  end
end
