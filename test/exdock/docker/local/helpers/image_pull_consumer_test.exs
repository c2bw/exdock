defmodule Exdock.Docker.Local.Helpers.ImagePullConsumerTest do
  use ExUnit.Case, async: true

  alias Exdock.Protocol.Messages
  alias Exdock.Docker.Error
  alias Exdock.Docker.Local.Helpers.ImagePullConsumer

  test "returns an HTTP error message for previously unhandled statuses" do
    handler = start_handler()

    send_stream(handler, {:status, 401, "Unauthorized"})
    send_stream(handler, ~s({"message":"authentication required"}))
    finish_stream(handler)

    assert_receive {:image_pull_error,
                    %Error{
                      operation: :image_pull,
                      status: 401,
                      cause: {:docker_stream, "authentication required"},
                      message: "authentication required"
                    }}
  end

  test "treats Docker errors inside a successful HTTP stream as failures" do
    handler = start_handler()

    send_stream(handler, {:status, 200, "OK"})
    send_stream(handler, ~s({"errorDetail":{"message":"manifest unknown"}}))
    finish_stream(handler)

    assert_receive {:image_pull_error,
                    %Error{
                      operation: :image_pull,
                      status: 200,
                      cause: {:docker_stream, "manifest unknown"},
                      message: "manifest unknown"
                    }}
  end

  test "returns a fallback error when a failed response has no message" do
    handler = start_handler()

    send_stream(handler, {:status, 429, "Too Many Requests"})
    finish_stream(handler)

    assert_receive {:image_pull_error,
                    %Error{
                      operation: :image_pull,
                      status: 429,
                      cause: {:http_status, "Too Many Requests"},
                      retryable?: true
                    }}
  end

  test "returns a fallback error when the stream ends without a status" do
    handler = start_handler()
    finish_stream(handler)

    assert_receive {:image_pull_error,
                    %Error{
                      operation: :image_pull,
                      cause: :missing_http_status,
                      message: "Docker pull ended without an HTTP status"
                    }}
  end

  test "reports request startup failures to the pull caller" do
    handler = start_handler()
    send(handler, {:stream_request_result, {:error, :econnrefused}})

    assert_receive {:image_pull_error,
                    %Error{
                      operation: {:image_pull, :stream_request},
                      cause: :econnrefused,
                      retryable?: true
                    }},
                   1_000
  end

  test "reports real hackney stream failures without waiting for inactivity timeout" do
    handler = start_handler()
    ref = Process.monitor(handler)
    send_stream(handler, {:error, :closed})
    assert_receive {:DOWN, ^ref, :process, ^handler, :normal}, 1_000

    assert_receive {:image_pull_error,
                    %Error{
                      operation: {:image_pull, :stream},
                      cause: :closed,
                      retryable?: true
                    }}
  end

  test "retains Docker error records split across transport chunks" do
    handler = start_handler()

    send_stream(handler, {:status, 200, "OK"})
    send_stream(handler, ~s({"errorDetail":{"message":"manifest))
    send_stream(handler, ~s( unknown"}}\n))
    finish_stream(handler)

    assert_receive {:image_pull_error, %Error{operation: :image_pull, cause: {:docker_stream, "manifest unknown"}}},
                   1_000
  end

  test "decodes multiple Docker records combined in one transport chunk" do
    handler = start_handler()

    send_stream(handler, {:status, 200, "OK"})
    send_stream(handler, ~s({"status":"Pulling manifest"}\r\n{"error":"access denied"}\r\n))
    finish_stream(handler)

    assert_receive {:image_pull_error, %Error{operation: :image_pull, cause: {:docker_stream, "access denied"}}}
  end

  test "does not report success when the final JSON record is malformed" do
    handler = start_handler()

    send_stream(handler, {:status, 200, "OK"})
    send_stream(handler, ~s({"error":"access denied"))
    finish_stream(handler)

    assert_receive {:image_pull_error,
                    %Error{
                      operation: {:image_pull, :stream_decode},
                      cause: {:malformed_json, ~s({"error":"access denied")},
                      message: "Docker pull stream contained malformed JSON"
                    }}
  end

  test "reports successful completed streams" do
    handler = start_handler()

    send_stream(handler, {:status, 200, "OK"})
    finish_stream(handler)

    assert_receive :image_pull_complete
  end

  test "recognizes Docker 29 progress payloads without the legacy progress bar field" do
    handler = start_handler()

    send_stream(
      handler,
      ~s({"status":"Downloading","progressDetail":{"current":4096,"total":8192},"id":"layer-1"})
    )

    assert_receive {:"$gen_cast",
                    {:send_update, %Messages.Update{id: "job-id", name: :image_pull, data: "download: 4.1 KB/8.19 KB"}}},
                   1_000
  end

  test "throttles progress with an injected monotonic clock" do
    clock = start_supervised!({Agent, fn -> [0, 25, 50] end})
    clock_fun = fn -> Agent.get_and_update(clock, fn [now | rest] -> {now, rest} end) end
    handler = start_handler(clock: clock_fun)

    send_progress(handler, 1)
    send_progress(handler, 2)
    send_progress(handler, 3)
    _state = :sys.get_state(handler)

    assert_receive {:"$gen_cast", {:send_update, %Messages.Update{data: "download: 1.0 B/10.0 B"}}}
    assert_receive {:"$gen_cast", {:send_update, %Messages.Update{data: "download: 3.0 B/10.0 B"}}}
    refute_receive {:"$gen_cast", {:send_update, %Messages.Update{data: "download: 2.0 B/10.0 B"}}}
  end

  defp start_handler(opts \\ []) do
    name = {:global, {__MODULE__, System.unique_integer([:positive])}}
    opts = Keyword.put(opts, :dispatcher, self())
    start_supervised!({ImagePullConsumer, {name, {self(), :image_pull, "job-id"}, opts}})
  end

  defp finish_stream(handler) do
    ref = Process.monitor(handler)
    send_stream(handler, :done)
    assert_receive {:DOWN, ^ref, :process, ^handler, :normal}, 1_000
  end

  defp send_stream(handler, body), do: send(handler, {:hackney_response, make_ref(), body})

  defp send_progress(handler, current) do
    send_stream(
      handler,
      ~s({"status":"Downloading","progressDetail":{"current":#{current},"total":10},"id":"layer"})
    )
  end
end
