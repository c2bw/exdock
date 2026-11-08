defmodule Exdock.Database.PersistedPayload do
  @moduledoc """
  Encodes and decodes compressed JSON payloads stored in encrypted columns.

  Current payloads are Base64-wrapped gzip data. Decoding also accepts the
  legacy raw-gzip representation, and always reports malformed data as a tagged
  error instead of raising in a persistence caller.
  """

  @spec encode(term()) :: {:ok, String.t()} | {:error, term()}
  def encode(data) do
    with {:ok, json} <- Jason.encode(data),
         {:ok, compressed} <- gzip(json) do
      {:ok, Base.encode64(compressed)}
    end
  end

  @spec decode(binary()) :: {:ok, term()} | {:error, term()}
  def decode(data) when is_binary(data) do
    data
    |> decode_payload_blob()
    |> gunzip()
    |> case do
      {:ok, json} -> Jason.decode(json)
      {:error, _reason} = error -> error
    end
  end

  def decode(data), do: {:error, {:invalid_persisted_payload, data}}

  defp decode_payload_blob(data) do
    case Base.decode64(data) do
      {:ok, compressed} -> compressed
      :error -> data
    end
  end

  defp gzip(data) do
    {:ok, :zlib.gzip(data)}
  rescue
    error -> {:error, {:gzip_failed, Exception.message(error)}}
  end

  defp gunzip(data) do
    {:ok, :zlib.gunzip(data)}
  rescue
    error -> {:error, {:gunzip_failed, Exception.message(error)}}
  end
end
