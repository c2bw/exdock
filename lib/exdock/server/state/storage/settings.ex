defmodule Exdock.Server.State.Storage.Settings do
  @moduledoc """
  In-memory storage for user-facing server settings.

  Settings are persisted in database tables owned by the underlying structures
  and loaded into server state at startup. Changes are written through the same
  state-change pipeline as other storage modules so LiveViews receive a forced
  settings broadcast after persistence.
  """

  require Logger
  alias Exdock.Configuration
  alias Exdock.Server.State.Storage.Persistence.UserSettings, as: UserSettingsPersistence
  alias Exdock.Server.State.Storage.Settings.Importer
  alias Exdock.Domain

  defstruct [
    :user
  ]

  @type t :: %__MODULE__{
          user: %{String.t() => Domain.UserSettings.t()}
        }

  @spec load() :: t()
  def load() do
    user = default_user()

    %__MODULE__{
      user: %{user => UserSettingsPersistence.load(user)}
    }
  end

  @doc """
  User settings for the default user.
  """
  @spec get(t()) :: Domain.UserSettings.t()
  def get(%__MODULE__{} = settings), do: %Domain.UserSettings{} = get(settings, default_user())

  @spec set(t(), String.t(), Domain.UserSettings.t()) :: t()
  defp set(%__MODULE__{user: users} = settings, user, %Domain.UserSettings{} = user_settings)
       when is_binary(user) do
    %{settings | user: Map.put(users, user, user_settings)}
  end

  @spec get(t(), String.t()) :: Domain.UserSettings.t() | nil
  defp get(%__MODULE__{user: users}, user) when is_binary(user), do: Map.get(users, user)

  defp default_user, do: Domain.UserSettings.default_user()

  defp current_default_user_settings(%__MODULE__{} = settings) do
    user = default_user()

    Map.get(settings.user, user) || UserSettingsPersistence.load(user)
  end

  @spec change_user_setting(t(), atom(), term()) :: {:ok, t()} | {:error, term()}
  def change_user_setting(%__MODULE__{} = settings, key, value) do
    with {:ok, {key, value}} <- Domain.UserSettings.validate_setting(key, value) do
      user_settings =
        settings
        |> current_default_user_settings()
        |> Domain.UserSettings.set(key, value)

      case persist_user_settings(user_settings) do
        :ok -> {:ok, put_default_user_settings(user_settings, settings)}
        {:error, reason} -> {:error, {:user_settings_persistence, reason}}
      end
    end
  end

  @spec import(Configuration.t()) ::
          {:ok, t(), Exdock.Server.State.Storage.Settings.Importer.Report.t()}
          | {:error, term()}
  def import(%Configuration{} = configuration) do
    case import_settings(configuration) do
      {:ok, report} -> {:ok, load(), report}
      {:error, reason} -> {:error, {:settings_import, reason}}
    end
  end

  defp log_error_result({:error, error}, message), do: Logger.error("#{message}: #{inspect(error)}")

  defp persist_user_settings(%Domain.UserSettings{} = user_settings) do
    case UserSettingsPersistence.insert(user_settings) do
      {:ok, _result} ->
        :ok

      {:error, reason} = error ->
        log_error_result(error, "Failed to insert user_settings")
        {:error, reason}
    end
  end

  defp put_default_user_settings(%Domain.UserSettings{} = user_settings, %__MODULE__{} = settings) do
    set(settings, default_user(), user_settings)
  end

  defp import_settings(%Configuration{} = configuration) do
    case Importer.import(configuration) do
      {:ok, report} ->
        {:ok, report}

      {:error, reason} = error ->
        log_error_result(error, "Failed to import settings")
        {:error, reason}
    end
  end
end
