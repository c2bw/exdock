defmodule Exdock.Database.UserSettings do
  @moduledoc """
  Persistence for application-wide user preferences.

  Exdock currently stores a single logical user's UI and automation settings.
  The storage persistence adapter maps this schema to runtime settings, which
  drive page-load refreshes, render diagnostics, resource polling, and
  automation scheduling.
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias Exdock.Database
  alias Exdock.Settings.UserFieldCatalog

  @persisted_fields UserFieldCatalog.keys()

  @type t :: %Database.UserSettings{
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

  @primary_key {:user, :string, autogenerate: false}
  schema "user_settings" do
    field :pageload_node_refresh, :boolean
    field :rendering_statistics, :boolean
    field :container_resources, :boolean
    field :automation_enabled, :boolean
    field :auto_update_above, :integer
    field :auto_update_containers, :boolean
    field :auto_update_releases, :boolean
    field :cron_string, :string
  end

  @spec new(map()) :: t()
  def new(attributes) when is_map(attributes),
    do: struct!(__MODULE__, UserFieldCatalog.take_required!(attributes, [:user]))

  @doc """
    Retrieve the settings.

    If no settings are found, the default is returned.
  """
  @spec load(String.t()) :: Database.UserSettings.t() | nil
  def load(user) when is_binary(user) do
    Exdock.Repo.get_by(Database.UserSettings, user: user)
  end

  @doc """
    Insert the settings.
  """
  @spec insert(Database.UserSettings.t(), keyword()) :: {:ok, Database.UserSettings.t()} | {:error, Ecto.Changeset.t()}
  def insert(%__MODULE__{} = settings, opts \\ []) do
    # User settings are treated as replaceable configuration; imports and UI
    # changes both upsert the single row for the user.
    opts = opts |> Keyword.put_new(:on_conflict, :replace_all)

    settings
    |> changeset(Map.take(settings, @persisted_fields))
    |> Exdock.Repo.insert(opts)
  end

  @doc """
    Removes all settings.
  """
  @spec purge() :: {non_neg_integer(), nil | [term()]}
  def purge() do
    Database.UserSettings
    |> Exdock.Repo.delete_all()
  end

  defp changeset(struct, params) do
    struct
    |> cast(params, @persisted_fields)
    |> validate_required([:user | @persisted_fields])
  end
end
