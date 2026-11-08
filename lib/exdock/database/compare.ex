defmodule Exdock.Database.Compare do
  @type comparable :: list() | struct() | map()

  @doc """
  Compare nested list/map/struct values after normalization.

  This intentionally ignores map keys and ordering. It is used for persistence
  snapshots where the relevant question is whether the stored values changed,
  while metadata and map/list ordering noise should not force a write.
  """
  @spec compare(comparable(), comparable()) :: boolean()
  def compare(a, b) do
    comparable_values(a) == comparable_values(b)
  end

  defp comparable_values(data) when is_struct(data) do
    data
    |> Map.from_struct()
    |> comparable_values()
  end

  defp comparable_values(data) when is_map(data) do
    data
    |> without_ecto_metadata()
    |> Map.values()
    |> normalized_value_bag()
  end

  defp comparable_values(data) when is_list(data), do: normalized_value_bag(data)

  defp flatten_value(value) when is_map(value) or is_list(value) do
    [comparable_values(value)]
  end

  defp flatten_value(other) do
    [other]
  end

  defp normalized_value_bag(values) when is_list(values) do
    values
    |> Enum.flat_map(&flatten_value/1)
    |> Enum.sort()
  end

  defp without_ecto_metadata(map), do: Map.delete(map, :__meta__)
end
