defmodule Exdock.Database.SchemaHelpers do
  @moduledoc """
  Shared mechanics for explicit Ecto schema boundaries.

  Schemas keep ownership of their changesets and runtime conversion functions;
  this module only handles repeated result mapping and validated bulk-row
  construction.
  """

  @spec map_ok({:ok, term()} | {:error, term()}, (term() -> term())) ::
          {:ok, term()} | {:error, term()}
  def map_ok({:ok, value}, mapper) when is_function(mapper, 1),
    do: {:ok, mapper.(value)}

  def map_ok({:error, _reason} = error, mapper) when is_function(mapper, 1),
    do: error

  @spec validated_rows([struct()], (struct() -> Ecto.Changeset.t()), [atom()]) ::
          {:ok, [map()]} | {:error, Ecto.Changeset.t()}
  def validated_rows(records, changeset_builder, schema_fields)
      when is_list(records) and is_function(changeset_builder, 1) and
             is_list(schema_fields) do
    Exdock.Result.traverse(records, fn record ->
      changeset = changeset_builder.(record)

      if changeset.valid? do
        row =
          changeset
          |> Ecto.Changeset.apply_changes()
          |> Map.from_struct()
          |> Map.take(schema_fields)

        {:ok, row}
      else
        {:error, changeset}
      end
    end)
  end
end
