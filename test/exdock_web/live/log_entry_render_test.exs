defmodule ExdockWeb.LogEntryRenderTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias ExdockWeb.PageLive.Log.Entry
  alias ExdockWeb.PageLive.LogModal.Entry, as: ModalEntry

  @events [
    {:container_status, {"node-a", "api", :unknown, :updated}},
    {:registry_fetch, 2},
    {:releases_fetch, %{repos_count: 2, new_releases_count: 1}},
    {:node_refresh,
     %{
       nodes: ["node-a"],
       containers: %{
         "node-a" => [
           {"new", {:new, true}},
           {"gone", {:ok, :vanished}},
           {"started", {:ok, true}},
           {"stopped", {:ok, false}},
           {"failed", {:error, :timeout}}
         ]
       }
     }},
    {:container_recreate, {:mass, {2, ["api", "worker"], true}}},
    {:container_restart, {"node-a", "api"}},
    {:node_connected, "node-a"},
    {:limited_entries, nil},
    {:no_log, nil}
  ]

  test "compact log entries render every presentation family" do
    for {{message_id, message_data}, index} <- Enum.with_index(@events) do
      html =
        render_component(&Entry.render/1, %{
          id: "compact-#{index}",
          entry_data: %{status: :finished},
          message_id: message_id,
          message_data: message_data
        })

      assert html =~ "<tr"
    end

    assert render_compact(:node_disconnected, "node-a", nil) =~ "node-a"
  end

  test "detailed log entries render timing, automation, and expanded changes" do
    start_time = ~U[2026-01-01 10:00:00.000Z]
    end_time = ~U[2026-01-01 10:00:01.250Z]

    for {{message_id, message_data}, index} <- Enum.with_index(@events) do
      html =
        render_component(&ModalEntry.render/1, %{
          id: "detail-#{index}",
          entry_data: %{status: :errored},
          message_id: message_id,
          message_data: message_data,
          start_time: start_time,
          end_time: end_time,
          automated: true
        })

      assert html =~ "detail-#{index}"
      assert html =~ "1.25s"
    end

    html = render_detailed(:node_refresh, %{nodes: ["node-a"], containers: %{"node-a" => [{"api", {:before, :updated}}]}})
    assert html =~ "node-a"
  end

  defp render_compact(message_id, message_data, entry_data) do
    render_component(&Entry.render/1, %{
      id: "compact-extra",
      entry_data: entry_data,
      message_id: message_id,
      message_data: message_data
    })
  end

  defp render_detailed(message_id, message_data) do
    render_component(&ModalEntry.render/1, %{
      id: "detail-extra",
      entry_data: nil,
      message_id: message_id,
      message_data: message_data,
      start_time: ~U[2026-01-01 10:00:00Z],
      end_time: nil,
      automated: false
    })
  end
end
