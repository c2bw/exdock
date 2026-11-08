defmodule Exdock.Domain.Container.Settings do
  @moduledoc """
  User-managed container settings persisted outside the Docker snapshot.

  Imports are permissive by design: invalid fields keep defaults instead of
  failing the whole settings import. `auto_update` is the only imported enum, so
  this module normalizes known string values to existing atoms before the shared
  import helper validates fields. No atoms are created from user input.
  """

  alias Exdock.Container.{Policy, SettingsCatalog}
  alias Exdock.Domain.ImportFields

  @derive Jason.Encoder
  defstruct [
    :priority,
    :auto_update,
    :labels
  ]

  @import_fields [
    {"priority", :priority, &__MODULE__.valid_priority?/1},
    {"auto_update", :auto_update, &__MODULE__.valid_auto_update?/1},
    {"labels", :labels, &__MODULE__.valid_labels?/1}
  ]

  @type auto_update :: :enabled | :disabled | :passthrough
  @type t :: %__MODULE__{
          priority: integer(),
          auto_update: auto_update(),
          labels: [String.t()]
        }
  @spec set_priority(t(), non_neg_integer()) :: t()
  def set_priority(%__MODULE__{} = settings, priority), do: set(settings, :priority, priority)

  @spec set_auto_update(t(), auto_update()) :: t()
  def set_auto_update(%__MODULE__{} = settings, auto_update), do: set(settings, :auto_update, auto_update)

  @spec default() :: t()
  def default(), do: struct(__MODULE__, SettingsCatalog.defaults())

  @doc """
  Build container settings from imported data.

  Invalid fields retain their defaults.
  """
  @spec from_import(map()) :: t()
  def from_import(%{} = unsafe) do
    default()
    |> ImportFields.apply_fields(normalize_import_fields(unsafe), @import_fields, &set/3)
  end

  @doc false
  defdelegate valid_priority?(value), to: Policy

  @doc false
  defdelegate valid_auto_update?(value), to: SettingsCatalog

  @doc false
  def valid_labels?(value), do: is_list(value) and Enum.all?(value, &is_binary/1)

  defp set(%__MODULE__{} = settings, :auto_update, value) do
    if SettingsCatalog.valid_auto_update?(value),
      do: %{settings | auto_update: value},
      else: settings
  end

  defp set(%__MODULE__{} = s, :priority, v) when is_integer(v) do
    if valid_priority?(v), do: %{s | priority: v}, else: s
  end

  defp set(%__MODULE__{} = s, :labels, v) when is_list(v), do: %{s | labels: v}

  defp normalize_import_fields(%{} = unsafe) do
    case Map.fetch(unsafe, "auto_update") do
      {:ok, value} -> %{unsafe | "auto_update" => SettingsCatalog.parse_auto_update(value)}
      :error -> unsafe
    end
  end

  @doc false
  @spec from_persisted(map()) :: t()
  def from_persisted(%{priority: priority, auto_update: auto_update, labels: labels}) do
    %__MODULE__{
      priority: priority,
      auto_update: auto_update,
      labels: labels
    }
  end
end
