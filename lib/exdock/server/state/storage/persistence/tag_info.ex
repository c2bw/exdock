defmodule Exdock.Server.State.Storage.Persistence.TagInfo do
  @moduledoc """
  Repository and mapper for remote registry tag metadata.
  """

  alias Exdock.Database
  alias Exdock.Domain.TagInfo

  @spec load_all() :: [TagInfo.t()]
  def load_all do
    Database.ImageTagInfo.load_all()
    |> Enum.map(&TagInfo.from_persisted/1)
  end

  @spec load(String.t(), String.t()) :: TagInfo.t() | nil
  def load(tag, platform) when is_binary(tag) and is_binary(platform) do
    case Database.ImageTagInfo.by_tag_and_platform(tag, platform) do
      nil -> nil
      %Database.ImageTagInfo{} = row -> TagInfo.from_persisted(row)
    end
  end

  @spec insert(TagInfo.t(), keyword()) ::
          {:ok, Database.ImageTagInfo.t()} | {:error, Ecto.Changeset.t()}
  def insert(%TagInfo{} = tag_info, opts \\ []) do
    tag_info
    |> Map.from_struct()
    |> Database.ImageTagInfo.new()
    |> Database.ImageTagInfo.insert(opts)
  end

  @spec insert_if_not_exists(TagInfo.t(), keyword()) ::
          {:ok, Database.ImageTagInfo.t()} | {:error, Ecto.Changeset.t()}
  def insert_if_not_exists(%TagInfo{} = tag_info, opts \\ []) do
    insert(tag_info, Keyword.put(opts, :on_conflict, :nothing))
  end
end
