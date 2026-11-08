defmodule Exdock.ReadModel.Value do
  @moduledoc false

  @calendar_structs [Date, DateTime, NaiveDateTime, Time]

  @spec project(term()) :: term()
  def project(%module{} = value) when module in @calendar_structs, do: value

  def project(%_module{} = value) do
    value
    |> Map.from_struct()
    |> project()
  end

  def project(value) when is_map(value) do
    Map.new(value, fn {key, nested_value} -> {key, project(nested_value)} end)
  end

  def project(value) when is_list(value), do: Enum.map(value, &project/1)
  def project(value) when is_tuple(value), do: value |> Tuple.to_list() |> Enum.map(&project/1) |> List.to_tuple()
  def project(value), do: value
end
