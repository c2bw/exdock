defmodule Exdock.Protocol.Snapshot.Image do
  @moduledoc "Protocol-owned representation of one Docker image snapshot."

  defstruct [:id, :name, :tags, :digest, :size, :shared_size, :build_date, repo_digests: []]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          tags: [String.t()],
          digest: String.t(),
          repo_digests: [String.t()],
          size: integer(),
          shared_size: integer(),
          build_date: DateTime.t()
        }

  @spec to_wire(t()) :: map()
  def to_wire(%__MODULE__{} = image) do
    %{
      "id" => image.id,
      "name" => image.name,
      "tags" => image.tags,
      "digest" => image.digest,
      "repo_digests" => image.repo_digests,
      "size" => image.size,
      "shared_size" => image.shared_size,
      "build_date" => encode_datetime(image.build_date)
    }
  end

  @spec from_wire(term()) :: {:ok, t()} | {:error, :invalid_image_snapshot}
  def from_wire(
        %{
          "id" => id,
          "name" => name,
          "tags" => tags,
          "digest" => digest,
          "size" => size,
          "shared_size" => shared_size,
          "build_date" => build_date
        } = payload
      )
      when is_binary(id) and is_binary(name) and is_list(tags) and
             is_integer(size) and is_integer(shared_size) do
    with {:ok, build_date} <- decode_datetime(build_date),
         repo_digests when is_list(repo_digests) <- Map.get(payload, "repo_digests", []),
         true <- Enum.all?(repo_digests, &is_binary/1) do
      {:ok,
       %__MODULE__{
         id: id,
         name: name,
         tags: tags,
         digest: digest,
         repo_digests: repo_digests,
         size: size,
         shared_size: shared_size,
         build_date: build_date
       }}
    else
      _invalid -> {:error, :invalid_image_snapshot}
    end
  end

  def from_wire(_payload), do: {:error, :invalid_image_snapshot}

  defp encode_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp encode_datetime(value), do: value

  defp decode_datetime(%DateTime{} = datetime), do: {:ok, datetime}

  defp decode_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _error -> :error
    end
  end

  defp decode_datetime(_value), do: :error
end
