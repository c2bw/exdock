defmodule Exdock.Server.State.Storage.Persistence.UserSettings do
  @moduledoc """
  Repository and mapper for application-wide user settings.
  """

  alias Exdock.Database
  alias Exdock.Domain.UserSettings

  @spec load(String.t()) :: UserSettings.t()
  def load(user) when is_binary(user) do
    case Database.UserSettings.load(user) do
      nil -> UserSettings.default()
      %Database.UserSettings{} = row -> UserSettings.from_persisted(row)
    end
  end

  @spec insert(UserSettings.t()) ::
          {:ok, Database.UserSettings.t()} | {:error, Ecto.Changeset.t()}
  def insert(%UserSettings{} = settings) do
    settings
    |> Map.from_struct()
    |> Database.UserSettings.new()
    |> Database.UserSettings.insert()
  end

  @spec import(map(), String.t()) ::
          {:ok, Database.UserSettings.t()} | {:error, Ecto.Changeset.t()}
  def import(%{} = unsafe, user) when is_binary(user) do
    Database.UserSettings.purge()

    unsafe
    |> UserSettings.from_import(user)
    |> insert()
  end
end
