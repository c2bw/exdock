defmodule Exdock.Protocol.Contract do
  @moduledoc "Encodes and decodes standalone NodeWire application frames."

  alias Exdock.Protocol.{Compatibility, NodeWire, Payload}

  def current_version, do: Compatibility.wire_version()

  def encode!(name, payload) do
    with {:ok, payload} <- Payload.encode(name, payload),
         {:ok, bytes} <- NodeWire.encode(name, payload) do
      bytes
    else
      {:error, _reason} -> raise ArgumentError, "invalid #{name} payload"
    end
  end

  defdelegate decode(frame), to: NodeWire
end
