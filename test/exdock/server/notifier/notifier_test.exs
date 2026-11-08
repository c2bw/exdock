defmodule Exdock.Server.NotifierTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Exdock.Server.Notifier
  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.{Event, Result}
  alias Exdock.Domain.{Repository, TagInfo}

  test "starts in disabled state when Loki URL is not configured" do
    logger_handlers = [{:handler, :other, Logger, %{config: %{url: "should-ignore"}}}]

    notifier = start_supervised!({Notifier, name: nil, subscribe?: false, logger_handlers: logger_handlers})

    assert :disabled = Notifier.status(notifier)
  end

  test "starts in disabled state when Glasgow handler is configured without URL" do
    logger_handlers = [{:handler, :glasgow, Logger, %{config: %{url: nil}}}]

    notifier = start_supervised!({Notifier, name: nil, subscribe?: false, logger_handlers: logger_handlers})

    assert :disabled = Notifier.status(notifier)
  end

  test "notification helpers stay no-op when notifier is unavailable" do
    missing = :missing_test_notifier

    assert :disabled = Notifier.status(missing)

    capture_log(fn ->
      assert :ok = Notifier.notify_container_status("node-a", "container-a", :high, "old", "new", missing)

      assert :ok =
               Notifier.notify_repository_release(
                 %Repository.Release{
                   name: "repo",
                   version: "1.0.0",
                   release_url: "https://example.com/release",
                   time_released: DateTime.utc_now()
                 },
                 missing
               )

      assert :ok =
               Notifier.notify_image_tag(
                 %TagInfo{
                   tag: "latest",
                   platform: "linux/amd64",
                   latest_date: DateTime.utc_now(),
                   latest_digest: "sha256:deadbeef"
                 },
                 missing
               )
    end)
  end

  test "notification helpers enqueue structured payloads without querying status" do
    assert :ok = Notifier.notify_container_status("node-a", "container-a", :high, "old", "new", self())

    assert_receive {:"$gen_cast",
                    {:notify, :container_status,
                     %{
                       node: "node-a",
                       name: "container-a",
                       priority: :high,
                       old: "old",
                       new: "new"
                     }}}
  end

  test "enabled notifier handles queued domain notifications" do
    payload = %{node: "node-a", name: "api", priority: :high, old: "running", new: "stopped"}

    assert {:noreply, %Notifier{status: :enabled}} =
             Notifier.handle_cast({:notify, :container_status, payload}, %Notifier{status: :enabled})
  end

  test "logger filter ignores notifier caller metadata" do
    assert :ignore = Notifier.logger_filter(%{meta: %{caller: :notifier}}, [])
    assert :stop = Notifier.logger_filter(%{meta: %{caller: :other}}, [])
    assert :stop = Notifier.logger_filter(%{}, [])
  end

  test "typed failed job events reach the notifier" do
    event =
      Event.job_finished(
        %Jobs.Info{name: :image_pull, automated: true},
        Result.new("job-1", "node_a", nil, :registry_unavailable)
      )

    log =
      capture_log(fn ->
        assert {:noreply, %Notifier{status: :enabled}} =
                 Notifier.handle_info(event, %Notifier{status: :enabled})
      end)

    assert log =~ "job_name=image_pull"
    assert log =~ "job_id=job-1"
    assert log =~ "error=\"registry_unavailable\""
  end
end
