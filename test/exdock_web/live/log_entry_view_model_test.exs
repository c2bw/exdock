defmodule ExdockWeb.LogEntryViewModelTest do
  use ExUnit.Case, async: true

  alias ExdockWeb.PageLive.Log.EntryViewModel

  test "recognizes every log event family rendered by the UI" do
    events = [
      {:container_status, {"node-a", "api", :unknown, :updated}, :container_status},
      {:registry_fetch, 2, :text},
      {:releases_fetch, %{repos_count: 2, new_releases_count: 1}, :releases_fetch},
      {:node_refresh, %{nodes: ["node-a"], containers: %{}}, :node_refresh},
      {:container_recreate, {:mass, {2, ["api", "worker"], false}}, :list},
      {:container_recreate, {"node-a", "api"}, :node_action},
      {:container_start, {"node-a", "api"}, :node_action},
      {:container_stop, {"node-a", "api"}, :node_action},
      {:container_restart, {"node-a", "api"}, :node_action},
      {:container_logs, {"node-a", "api"}, :node_action},
      {:image_delete, {"node-a", "sha256:abc"}, :node_action},
      {:image_pull, {:mass, {2, ["api:latest", "worker:latest"]}}, :list},
      {:image_pull, {"node-a", "api:latest"}, :node_action},
      {:node_connected, "node-a", :node_state},
      {:node_disconnected, "node-a", :node_state},
      {:repository_overrides, {2}, :text},
      {:containers_priorities, {2}, :text},
      {:limited_entries, nil, :limited_entries},
      {:no_log, nil, :text}
    ]

    for {message_id, message_data, expected_kind} <- events do
      assert %{kind: ^expected_kind} = EntryViewModel.build(message_id, message_data)
    end
  end

  test "returns entries matching the public tagged presentation union" do
    assert %{kind: :limited_entries} = entry = EntryViewModel.build(:limited_entries, nil)
    assert Map.keys(entry) == [:kind]

    assert %{kind: :unknown, message_id: :other, message_data: %{value: 1}} =
             EntryViewModel.build(:other, %{value: 1})
  end

  test "normalizes shared action labels and pluralization" do
    assert %{kind: :text, text: "fetch [1] image"} = EntryViewModel.build(:registry_fetch, 1)
    assert %{kind: :text, text: "fetch [2] images"} = EntryViewModel.build(:registry_fetch, 2)

    assert %{kind: :node_action, text: "restart [api]", detailed_text: "restart [api] node [node-a]"} =
             EntryViewModel.build(:container_restart, {"node-a", "api"})

    assert %{kind: :text, text: "set 1 repository URL"} =
             EntryViewModel.build(:repository_overrides, {1})

    assert %{kind: :text, text: "set 2 container priorities"} =
             EntryViewModel.build(:containers_priorities, {2})
  end

  test "preserves compact and detailed mass-action text" do
    assert %{
             kind: :list,
             text: "mass recreate [2] containers",
             detailed_text: "mass pull and recreate [2] containers",
             list: ["node-a,api", "node-b,worker"]
           } =
             EntryViewModel.build(
               :container_recreate,
               {:mass, {2, ["node-a,api", "node-b,worker"], true}}
             )
  end

  test "builds refresh counts and detailed changes once" do
    containers = %{
      "node-a" => [
        {"new", {:new, true}},
        {"gone", {:ok, :vanished}},
        {"started", {:ok, true}},
        {"stopped", {:ok, false}},
        {"failed", {:error, :timeout}}
      ]
    }

    assert %{
             kind: :node_refresh,
             text: "refresh [1] node",
             nodes: ["node-a"],
             detailed?: true,
             counts: %{new: 1, vanished: 1, started: 1, stopped: 1, errored: 1},
             changes: changes
           } = EntryViewModel.build(:node_refresh, %{nodes: ["node-a"], containers: containers})

    assert length(changes) == 5
  end

  test "uses the summary-only refresh mode when before snapshots are present" do
    containers = %{"node-a" => [{"api", {:before, :updated}}]}

    assert %{detailed?: false, changes: []} =
             EntryViewModel.build(:node_refresh, %{nodes: ["node-a"], containers: containers})
  end

  test "normalizes job status presentation" do
    assert EntryViewModel.status(nil) == nil

    assert EntryViewModel.status(%{status: :started}).icon == "hero-command-line"
    assert EntryViewModel.status(%{status: :finished}).icon == "hero-check-circle"
    assert EntryViewModel.status(%{status: :errored}).icon == "hero-exclamation-circle"
  end
end
