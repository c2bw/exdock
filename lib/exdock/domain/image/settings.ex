defmodule Exdock.Domain.Image.Settings do
  @moduledoc """
  In-memory representation of image settings stored in the database.

  Image settings currently track a single lock flag, while persistence and
  imports are delegated to this module's helper functions to keep behavior
  centralized.
  """
  alias Exdock.Domain.ImportFields

  @derive Jason.Encoder
  defstruct [
    :delete_lock
  ]

  @default_delete_lock false
  @import_fields [
    {"delete_lock", :delete_lock, &is_boolean/1}
  ]

  @type t :: %__MODULE__{
          delete_lock: boolean()
        }
  @spec set_delete_lock(t(), boolean()) :: t()
  def set_delete_lock(%__MODULE__{} = settings, lock) when is_boolean(lock), do: set(settings, :delete_lock, lock)

  defp set(%__MODULE__{} = s, :delete_lock, v) when is_boolean(v), do: %{s | delete_lock: v}

  @spec default() :: t()
  def default() do
    %__MODULE__{
      delete_lock: @default_delete_lock
    }
  end

  @doc """
  Build image settings from imported data.

  Invalid fields retain their defaults.
  """
  @spec from_import(map()) :: t()
  def from_import(%{} = unsafe) do
    default()
    |> ImportFields.apply_fields(unsafe, @import_fields, &set/3)
  end

  @doc false
  @spec from_persisted(map()) :: t()
  def from_persisted(%{delete_lock: delete_lock}) do
    %__MODULE__{delete_lock: delete_lock}
  end
end
