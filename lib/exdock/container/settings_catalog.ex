defmodule Exdock.Container.SettingsCatalog do
  @moduledoc """
  Canonical metadata for user-managed container settings.

  Runtime validation, imports, and database persistence consume this catalog so
  supported fields, enum values, and defaults cannot drift between layers.
  """

  @fields [:priority, :auto_update, :labels]
  @auto_update_values [:enabled, :disabled, :passthrough]
  @defaults %{priority: 3, auto_update: :passthrough, labels: []}
  @auto_update_import_values Map.new(@auto_update_values, &{Atom.to_string(&1), &1})

  @type field :: :priority | :auto_update | :labels
  @type auto_update :: :enabled | :disabled | :passthrough

  @spec fields() :: [field()]
  def fields, do: @fields

  @spec defaults() :: %{required(field()) => term()}
  def defaults, do: @defaults

  @spec default(field()) :: term()
  def default(field), do: Map.fetch!(@defaults, field)

  @spec auto_update_values() :: [auto_update()]
  def auto_update_values, do: @auto_update_values

  @spec valid_auto_update?(term()) :: boolean()
  def valid_auto_update?(value), do: value in @auto_update_values

  @spec parse_auto_update(term()) :: auto_update() | :invalid
  def parse_auto_update(value) when is_atom(value) do
    if valid_auto_update?(value), do: value, else: :invalid
  end

  def parse_auto_update(value) when is_binary(value),
    do: Map.get(@auto_update_import_values, value, :invalid)

  def parse_auto_update(_value), do: :invalid
end
