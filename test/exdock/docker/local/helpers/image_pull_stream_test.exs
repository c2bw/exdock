defmodule Exdock.Docker.Local.Helpers.ImagePullStreamTest do
  use ExUnit.Case, async: true

  alias Exdock.Docker.Local.Helpers.ImagePullStream
  alias Exdock.Docker.Error

  test "retains JSON records split across chunks" do
    stream = ImagePullStream.new()
    {stream, []} = ImagePullStream.consume(stream, ~s({"errorDetail":{"message":"manifest))
    {stream, []} = ImagePullStream.consume(stream, ~s( unknown"}}\n))

    assert {_stream, [],
            {:error,
             %Error{
               operation: :image_pull,
               status: 200,
               cause: {:docker_stream, "manifest unknown"}
             }}} =
             stream
             |> with_status(200)
             |> ImagePullStream.finish()
  end

  test "decodes combined records and preserves event order" do
    body =
      ~s({"status":"Downloading","progressDetail":{"current":1,"total":2},"id":"a"}\n) <>
        ~s({"status":"Extracting","progressDetail":{"current":2,"total":2},"id":"a"}\n)

    assert {_stream,
            [
              {:progress, "Downloading", 1, 2},
              {:progress, "Extracting", 2, 2}
            ]} = ImagePullStream.consume(ImagePullStream.new(), body)
  end

  test "uses Docker error details as the completion failure" do
    stream =
      ImagePullStream.new()
      |> with_status(200)
      |> consume(~s({"errorDetail":{"message":"manifest unknown"}}))

    assert {_stream, [],
            {:error,
             %Error{
               operation: :image_pull,
               status: 200,
               cause: {:docker_stream, "manifest unknown"}
             }}} = ImagePullStream.finish(stream)
  end

  test "rejects a malformed final record" do
    stream =
      ImagePullStream.new()
      |> with_status(200)
      |> consume(~s({"status":"Pulling"))

    assert {_stream, [],
            {:error,
             %Error{
               operation: {:image_pull, :stream_decode},
               cause: {:malformed_json, ~s({"status":"Pulling")},
               message: "Docker pull stream contained malformed JSON"
             }}} =
             ImagePullStream.finish(stream)
  end

  test "completes a successful HTTP stream" do
    assert {_stream, [], :ok} =
             ImagePullStream.new()
             |> with_status(200)
             |> ImagePullStream.finish()
  end

  test "retains failed HTTP status and reason without formatting the cause" do
    assert {_stream, [],
            {:error,
             %Error{
               operation: :image_pull,
               status: 503,
               cause: {:http_status, "Service Unavailable"},
               retryable?: true
             }}} =
             ImagePullStream.new()
             |> with_status(503, "Service Unavailable")
             |> ImagePullStream.finish()
  end

  test "returns a typed error when the transport never supplies a status" do
    assert {_stream, [],
            {:error,
             %Error{
               operation: :image_pull,
               cause: :missing_http_status
             }}} = ImagePullStream.finish(ImagePullStream.new())
  end

  defp with_status(stream, status, reason \\ "status") do
    {stream, []} = ImagePullStream.consume(stream, {:status, status, reason})
    stream
  end

  defp consume(stream, body) do
    {stream, _events} = ImagePullStream.consume(stream, body)
    stream
  end
end
