defmodule Exdock.Server.State.Storage.Persistence.PersistedStruct do
  @moduledoc """
  Rebuilds known structs from persistence maps without creating atoms.

  Persistence payloads may contain atom keys, string keys, or a mixture of
  both. String keys take precedence so decoded database values cannot be
  shadowed by stale atom-keyed defaults.
  """

  @spec decode(map(), module()) :: struct()
  def decode(attributes, module) when is_map(attributes) and is_atom(module) do
    values =
      module
      |> struct!()
      |> Map.keys()
      |> List.delete(:__struct__)
      |> Map.new(fn field -> {field, value(attributes, field)} end)

    struct!(module, values)
  end

  defp value(attributes, field) do
    case Map.fetch(attributes, Atom.to_string(field)) do
      {:ok, value} -> value
      :error -> Map.get(attributes, field)
    end
  end
end
