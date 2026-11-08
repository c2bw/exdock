defmodule Exdock.Settings.UserFieldCatalog do
  @moduledoc """
  Canonical metadata for persisted and operator-editable user settings.

  Validation implementations remain with the runtime settings structure, while
  this catalog owns field identity, external names, normalization kinds, and
  defaults shared by imports, persistence adapters, and the public API.
  """

  @default_user "admin"

  @fields [
    %{external: "pageload_node_refresh", field: :pageload_node_refresh, kind: :boolean, default: false},
    %{external: "rendering_statistics", field: :rendering_statistics, kind: :boolean, default: false},
    %{external: "container_resources", field: :container_resources, kind: :boolean, default: false},
    %{external: "automation_enabled", field: :automation_enabled, kind: :boolean, default: false},
    %{external: "auto_update_above", field: :auto_update_above, kind: :priority_threshold, default: 3},
    %{external: "auto_update_containers", field: :auto_update_containers, kind: :boolean, default: true},
    %{external: "auto_update_releases", field: :auto_update_releases, kind: :boolean, default: true},
    %{external: "cron_string", field: :cron_string, kind: :cron, default: "0 22 * * *"}
  ]

  @fields_by_external Map.new(@fields, &{&1.external, &1})
  @fields_by_name Map.new(@fields, &{&1.field, &1})

  @type key ::
          :pageload_node_refresh
          | :rendering_statistics
          | :container_resources
          | :automation_enabled
          | :auto_update_above
          | :auto_update_containers
          | :auto_update_releases
          | :cron_string
  @type value :: boolean() | 0..4 | String.t()
  @type kind :: :boolean | :priority_threshold | :cron
  @type field :: %{external: String.t(), field: key(), kind: kind(), default: value()}

  @spec fields() :: [field()]
  def fields, do: @fields

  @spec keys() :: [key()]
  def keys, do: Enum.map(@fields, & &1.field)

  @spec defaults() :: keyword(value())
  def defaults, do: Enum.map(@fields, &{&1.field, &1.default})

  @spec default_user() :: String.t()
  def default_user, do: @default_user

  @spec resolve(term()) :: {:ok, key()} | :error
  def resolve(key) when is_atom(key) do
    case Map.fetch(@fields_by_name, key) do
      {:ok, field} -> {:ok, field.field}
      :error -> :error
    end
  end

  def resolve(key) when is_binary(key) do
    case Map.fetch(@fields_by_external, key) do
      {:ok, field} -> {:ok, field.field}
      :error -> :error
    end
  end

  def resolve(_key), do: :error

  @spec kind(key()) :: kind()
  def kind(key), do: @fields_by_name |> Map.fetch!(key) |> Map.fetch!(:kind)

  @spec external(key()) :: String.t()
  def external(key), do: @fields_by_name |> Map.fetch!(key) |> Map.fetch!(:external)

  @spec take_required!(map(), [atom()]) :: map()
  def take_required!(attributes, identity_fields \\ []) when is_map(attributes) and is_list(identity_fields) do
    Map.new(identity_fields ++ keys(), &{&1, Map.fetch!(attributes, &1)})
  end
end
