defmodule Exdock.ClientLib.Container.LogDecoder do
  @moduledoc """
  Decodes Docker container log responses.

  Non-TTY containers return multiplexed stdout and stderr frames. TTY
  containers return an unframed byte stream, which is preserved as one entry.
  """

  @type decode_error :: :malformed_frame

  @spec decode(binary()) :: {:ok, [String.t()]} | {:error, decode_error()}
  def decode(""), do: {:ok, []}

  def decode(<<stream, 0, 0, 0, _size::unsigned-big-32, _rest::binary>> = body)
      when stream in 0..2 do
    decode_frames(body, [])
  end

  def decode(body) when is_binary(body), do: {:ok, [body]}

  defp decode_frames("", frames), do: {:ok, Enum.reverse(frames)}

  defp decode_frames(
         <<stream, 0, 0, 0, size::unsigned-big-32, rest::binary>>,
         frames
       )
       when stream in 0..2 and byte_size(rest) >= size do
    <<payload::binary-size(^size), remaining::binary>> = rest
    decode_frames(remaining, [payload | frames])
  end

  defp decode_frames(_body, _frames), do: {:error, :malformed_frame}
end
