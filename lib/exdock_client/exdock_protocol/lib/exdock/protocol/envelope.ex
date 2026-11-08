defmodule Exdock.Protocol.Envelope do
  @moduledoc """
  Shared frame and safe-term decoding for protocol endpoints.

  Client and server codecs provide endpoint-specific payload validation while
  this module preserves framing errors and normalizes malformed payloads.
  """

  alias Exdock.Protocol.Contract

  @type payload_decoder ::
          (Contract.message_name(), binary() -> {:ok, term()} | {:error, Contract.decode_error()})

  @spec decode(term(), payload_decoder()) :: term()
  def decode(frame, payload_decoder) when is_binary(frame) and is_function(payload_decoder, 2) do
    with {:ok, message_name, payload} <- Contract.decode_frame(frame),
         {:ok, message} <- payload_decoder.(message_name, payload) do
      message
    end
  end

  def decode(_frame, _payload_decoder), do: {:error, :malformed_message}

  @spec decode_term(binary(), (term() -> {:ok, term()} | {:error, Contract.decode_error()})) ::
          {:ok, term()} | {:error, Contract.decode_error()}
  def decode_term(payload, build) when is_function(build, 1) do
    case Contract.decode_term(payload, [:safe]) do
      {:ok, term} -> build.(term)
      :error -> {:error, :malformed_message}
    end
  end
end
