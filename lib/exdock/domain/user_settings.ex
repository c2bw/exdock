defmodule Exdock.Domain.UserSettings do
  alias Exdock.Container.Policy
  alias Exdock.Schedule
  alias Exdock.Settings.UserFieldCatalog
  alias Exdock.Domain.ImportFields

  @setting_fields UserFieldCatalog.fields()

  @import_validators %{
    boolean: &is_boolean/1,
    priority_threshold: &__MODULE__.valid_update_threshold?/1,
    cron: &__MODULE__.valid_cron?/1
  }

  @import_fields Enum.map(@setting_fields, fn field ->
                   {field.external, field.field, Map.fetch!(@import_validators, field.kind)}
                 end)
  @setting_defaults UserFieldCatalog.defaults()

  @derive {Jason.Encoder, except: [:user]}
  defstruct [user: UserFieldCatalog.default_user()] ++ @setting_defaults

  @type t :: %__MODULE__{
          user: String.t(),
          pageload_node_refresh: boolean(),
          rendering_statistics: boolean(),
          container_resources: boolean(),
          automation_enabled: boolean(),
          auto_update_above: integer(),
          auto_update_containers: boolean(),
          auto_update_releases: boolean(),
          cron_string: String.t()
        }

  @spec default() :: t()
  def default(), do: %__MODULE__{}
  @spec default_user() :: String.t()
  defdelegate default_user(), to: UserFieldCatalog

  @spec set(t(), atom() | String.t(), term()) :: t()
  def set(%__MODULE__{} = settings, key, value) do
    case validate_setting(key, value) do
      {:ok, {key, value}} -> Map.replace!(settings, key, value)
      {:error, _reason} -> settings
    end
  end

  @doc false
  @spec setting_key(atom() | String.t()) :: {:ok, atom()} | :error
  defdelegate setting_key(key), to: UserFieldCatalog, as: :resolve

  @doc false
  @spec validate_setting(term(), term()) ::
          {:ok, {atom(), term()}}
          | {:error, {:unknown_user_setting, term()} | {:invalid_user_setting_value, atom()}}
  def validate_setting(key, value) do
    case setting_key(key) do
      {:ok, key} ->
        case normalize(setting_kind_for(key), value) do
          {:ok, value} -> {:ok, {key, value}}
          :error -> {:error, {:invalid_user_setting_value, key}}
        end

      :error ->
        {:error, {:unknown_user_setting, key}}
    end
  end

  defp set_user(%__MODULE__{} = s, v) when is_binary(v), do: %{s | user: v}

  @doc """
  Build user settings from imported data.

  Invalid fields retain their defaults.
  """
  @spec from_import(map(), String.t()) :: t()
  def from_import(%{} = unsafe, user) when is_binary(user) do
    default()
    |> set_user(user)
    |> ImportFields.apply_fields(unsafe, @import_fields, &set/3)
  end

  @doc false
  defdelegate valid_update_threshold?(value), to: Policy

  @doc false
  def valid_cron?(value), do: is_binary(value) and Schedule.valid?(value)

  defp setting_kind_for(key), do: UserFieldCatalog.kind(key)

  defp normalize(:boolean, value) when is_boolean(value), do: {:ok, value}
  defp normalize(:boolean, "true"), do: {:ok, true}
  defp normalize(:boolean, "false"), do: {:ok, false}
  defp normalize(:boolean, _value), do: :error

  defp normalize(:priority_threshold, value) when is_integer(value) do
    if valid_update_threshold?(value), do: {:ok, value}, else: :error
  end

  defp normalize(:priority_threshold, value) when is_binary(value) do
    case Integer.parse(value) do
      {threshold, ""} -> normalize(:priority_threshold, threshold)
      _ -> :error
    end
  end

  defp normalize(:priority_threshold, _value), do: :error

  # Cron strings come from both imports and LiveView events. Validate them here
  # so invalid scheduler expressions never get persisted into user settings.
  defp normalize(:cron, value) when is_binary(value) do
    if valid_cron?(value), do: {:ok, value}, else: :error
  end

  defp normalize(:cron, _value), do: :error

  @doc false
  @spec from_persisted(map()) :: t()
  def from_persisted(persisted) when is_map(persisted),
    do: struct!(__MODULE__, UserFieldCatalog.take_required!(persisted, [:user]))
end
