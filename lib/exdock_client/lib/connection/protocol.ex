defmodule Exdock.Client.Connection.Protocol do
  @moduledoc """
  Client codec for protocol v4.

  The base client understands only connection lifecycle messages, validated
  commands, and normalized runtime responses. Executable module/function tuples
  are not part of the protocol.
  """

  alias Exdock.Protocol.{Contract, Envelope, Message}

  def encode_message({:heartbeat}), do: Contract.encode_frame(:heartbeat, "")
  def encode_message({:error, reason}), do: Contract.encode_term_frame(:error, reason)
  def encode_message({:hello, hello}) when is_map(hello), do: Contract.encode_term_frame(:hello, hello)
  def encode_message({:ready, ready}) when is_map(ready), do: Contract.encode_term_frame(:ready, ready)

  def encode_message({:result, result}) when is_map(result) do
    if Message.valid_result?(result),
      do: Contract.encode_term_frame(:result, result),
      else: raise(ArgumentError, "invalid result")
  end

  def encode_message({:progress, progress}) when is_map(progress) do
    if Message.valid_progress?(progress),
      do: Contract.encode_term_frame(:progress, progress),
      else: raise(ArgumentError, "invalid progress")
  end

  def encode_message({:resource_sample, sample}) when is_map(sample) do
    if Message.valid_resource_sample?(sample),
      do: Contract.encode_term_frame(:resource_sample, sample),
      else: raise(ArgumentError, "invalid resource sample")
  end

  @spec decode_message(binary()) :: tuple()
  def decode_message(frame) when is_binary(frame) do
    Envelope.decode(frame, &decode_payload/2)
  end

  def decode_message(_frame), do: {:error, :malformed_message}

  defp decode_payload(:heartbeat, payload), do: {:ok, {:heartbeat, payload}}
  defp decode_payload(:error, payload), do: Envelope.decode_term(payload, &{:ok, {:error, &1}})

  defp decode_payload(:runtime_bundle, payload) do
    Envelope.decode_term(payload, fn
      %{"version" => version, "digest" => digest, "modules" => modules} = bundle
      when is_binary(version) and is_binary(digest) and is_list(modules) ->
        {:ok, {:runtime_bundle, bundle}}

      _payload ->
        {:error, :malformed_message}
    end)
  end

  defp decode_payload(:command, payload) do
    Envelope.decode_term(payload, fn payload ->
      if Message.valid_command?(payload), do: {:ok, {:command, payload}}, else: {:error, :malformed_message}
    end)
  end

  defp decode_payload(_message_name, _payload), do: {:error, :malformed_message}
end
