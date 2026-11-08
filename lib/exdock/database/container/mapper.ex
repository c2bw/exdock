defmodule Exdock.Database.Container.Mapper do
  @moduledoc """
  Converts container records to and from their persisted row representation.

  Runtime records contain decoded maps and canonical node identifiers. Stored
  rows contain validated node strings and compressed JSON payloads.
  """

  alias Exdock.Database.Container.Record
  alias Exdock.Database.Container.Row
  alias Exdock.Database.NodeName
  alias Exdock.Database.PersistedPayload

  @spec to_record(Row.t()) :: {:ok, Record.t()} | {:error, term()}
  def to_record(%{node: node, configuration: configuration, state: state} = container_row) do
    with {:ok, configuration} <- decode_payload(configuration, :configuration),
         {:ok, state} <- decode_payload(state, :state) do
      record =
        container_row
        |> Map.take(record_fields())
        |> Map.merge(%{
          node: NodeName.load(node),
          configuration: configuration,
          state: state
        })
        |> then(&struct!(Record, &1))

      {:ok, record}
    else
      {:error, reason} ->
        {:error, {:invalid_container_payload, node, container_row.name, reason}}
    end
  end

  @spec to_records([Row.t()]) :: {:ok, [Record.t()]} | {:error, term()}
  def to_records(rows) when is_list(rows) do
    Exdock.Result.traverse(rows, &to_record/1)
  end

  @spec to_row(Record.t()) :: {:ok, map()} | {:error, term()}
  def to_row(%Record{node: node, configuration: configuration, state: state} = container) do
    with {:ok, configuration} <- encode_payload(configuration, :configuration),
         {:ok, state} <- encode_payload(state, :state) do
      {:ok,
       container
       |> Map.from_struct()
       |> Map.merge(%{
         node: NodeName.dump(node),
         configuration: configuration,
         state: state
       })}
    end
  end

  @spec to_rows([Record.t()]) :: {:ok, [map()]} | {:error, term()}
  def to_rows(containers) when is_list(containers) do
    Exdock.Result.traverse(containers, &to_row/1)
  end

  defp encode_payload(data, field) do
    case PersistedPayload.encode(data) do
      {:ok, payload} -> {:ok, payload}
      {:error, reason} -> {:error, {:invalid_container_payload, field, reason}}
    end
  end

  defp decode_payload(data, field) do
    case PersistedPayload.decode(data) do
      {:ok, payload} when is_map(payload) -> {:ok, payload}
      {:ok, payload} -> {:error, {field, {:expected_object, payload}}}
      {:error, reason} -> {:error, {field, reason}}
    end
  end

  defp record_fields, do: %Record{} |> Map.keys() |> List.delete(:__struct__)
end
