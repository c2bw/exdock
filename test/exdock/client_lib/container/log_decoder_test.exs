defmodule Exdock.ClientLib.Container.LogDecoderTest do
  use ExUnit.Case, async: true

  alias Exdock.ClientLib.Container.LogDecoder

  test "decodes stdout and stderr frames using their declared sizes" do
    body = frame(1, "stdout\n") <> frame(2, "stderr\n")

    assert {:ok, ["stdout\n", "stderr\n"]} = LogDecoder.decode(body)
  end

  test "does not split header-like bytes inside a payload" do
    payload = <<"before", 1, 0, 0, 0, 0, 0, 0, 3, "end">>

    assert {:ok, [^payload]} = LogDecoder.decode(frame(1, payload))
  end

  test "preserves payload whitespace" do
    assert {:ok, ["  value \n"]} = LogDecoder.decode(frame(1, "  value \n"))
  end

  test "rejects truncated and invalid trailing frames" do
    assert {:error, :malformed_frame} = LogDecoder.decode(<<1, 0, 0, 0, 0, 0, 0, 4, "abc">>)
    assert {:error, :malformed_frame} = LogDecoder.decode(frame(1, "ok") <> <<9, 0, 0, 0, 0, 0, 0, 0>>)
  end

  test "preserves an unframed TTY stream" do
    assert {:ok, ["first\nsecond\n"]} = LogDecoder.decode("first\nsecond\n")
  end

  test "decodes an empty response" do
    assert {:ok, []} = LogDecoder.decode("")
  end

  defp frame(stream, payload) do
    <<stream, 0, 0, 0, byte_size(payload)::unsigned-big-32, payload::binary>>
  end
end
