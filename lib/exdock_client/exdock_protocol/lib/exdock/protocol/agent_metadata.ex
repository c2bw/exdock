defmodule Exdock.Protocol.AgentMetadata do
  @moduledoc """
  Validation and sanitization for metadata reported by an authenticated agent.

  Known fields are retained at the protocol boundary while unknown fields are
  ignored, allowing future clients to add optional metadata without exposing
  arbitrary terms to server state.
  """

  @fields %{
    "platform" => 128,
    "agent_version" => 32,
    "elixir_version" => 32,
    "otp_release" => 32
  }

  @type t :: %{required(String.t()) => String.t()}

  @spec sanitize(term()) :: {:ok, t()} | {:error, :invalid_metadata}
  def sanitize(metadata) when is_map(metadata) do
    Enum.reduce_while(@fields, {:ok, %{}}, fn {field, max_length}, {:ok, sanitized} ->
      case Map.fetch(metadata, field) do
        {:ok, value} when is_binary(value) and byte_size(value) > 0 and byte_size(value) <= max_length ->
          {:cont, {:ok, Map.put(sanitized, field, value)}}

        _other ->
          {:halt, {:error, :invalid_metadata}}
      end
    end)
  end

  def sanitize(_metadata), do: {:error, :invalid_metadata}
end
