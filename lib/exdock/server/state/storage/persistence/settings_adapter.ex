defmodule Exdock.Server.State.Storage.Persistence.SettingsAdapter do
  @moduledoc false

  @spec load(term() | nil, (term() -> struct())) :: struct() | nil
  def load(nil, _from_persisted), do: nil
  def load(row, from_persisted) when is_function(from_persisted, 1), do: from_persisted.(row)

  @spec attributes(struct(), map()) :: map()
  def attributes(settings, identity) when is_struct(settings) and is_map(identity) do
    settings
    |> Map.from_struct()
    |> Map.merge(identity)
  end

  @spec import(map(), (map() -> struct()), (struct() -> term())) :: term()
  def import(unsafe, from_import, persist)
      when is_map(unsafe) and is_function(from_import, 1) and is_function(persist, 1) do
    unsafe
    |> from_import.()
    |> persist.()
  end
end
