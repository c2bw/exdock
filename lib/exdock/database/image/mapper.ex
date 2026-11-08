defmodule Exdock.Database.Image.Mapper do
  @moduledoc """
  Converts image records to and from their persisted row representation.
  """

  alias Exdock.Database.Image.Record
  alias Exdock.Database.Image.Row
  alias Exdock.Database.NodeName

  @spec to_row(Record.t()) :: map()
  def to_row(%Record{node: node, tags: tags} = image) do
    image
    |> Map.take(Record.fields())
    |> Map.merge(%{node: NodeName.stored!(node), tags: serialize_tags(tags)})
  end

  @spec to_rows([Record.t()]) :: [map()]
  def to_rows(images) when is_list(images), do: Enum.map(images, &to_row/1)

  @spec to_record(Row.t()) :: Record.t()
  def to_record(%Row{node: node, tags: tags} = image) do
    image
    |> Map.from_struct()
    |> Map.take(Record.fields())
    |> Map.put(:node, NodeName.load(node))
    |> Map.put(:tags, deserialize_tags(tags))
    |> then(&struct!(Record, &1))
  end

  @spec to_records([Row.t()]) :: [Record.t()]
  def to_records(images) when is_list(images), do: Enum.map(images, &to_record/1)

  @spec key(String.t(), String.t()) :: String.t()
  def key(node, id) when is_binary(node) and is_binary(id),
    do: "#{NodeName.stored!(node)}:#{id}"

  @spec serialize_tags([String.t()]) :: String.t()
  def serialize_tags(tags) when is_list(tags), do: Enum.join(tags, ",")

  @spec deserialize_tags(String.t() | nil) :: [String.t()]
  def deserialize_tags(nil), do: []
  def deserialize_tags(""), do: []
  def deserialize_tags(tags) when is_binary(tags), do: String.split(tags, ",")
end
