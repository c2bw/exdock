defmodule Exdock.Client.Connection.Protocol do
  @moduledoc "Client adapter for NodeWire application events."

  alias Exdock.Protocol.{Contract, Message, Payload}

  def encode_message({name, payload}), do: Contract.encode!(name, payload)

  def decode_message(frame) do
    case Contract.decode(frame) do
      {:ok, message} -> decode_event(message)
      {:error, _} -> {:error, :malformed_message}
    end
  end

  def decode_event({name, payload}) do
    with {:ok, payload} <- Payload.decode(name, payload) do
      case name do
        :runtime_bundle -> {:runtime_bundle, payload}
        :error -> {:error, payload}
        :command -> decode_command(payload)
        _ -> {:error, :malformed_message}
      end
    else
      {:error, _} -> {:error, :malformed_message}
    end
  end

  defp decode_command(payload) do
    if Message.valid_command?(payload), do: {:command, payload}, else: {:error, :malformed_message}
  end
end
