defmodule Exdock.Database.Repository do
  @moduledoc """
  Persistence for remote repository metadata.

  Repository URLs are the primary key. The stored metadata tracks the release
  page fetch state and last successful check so the in-memory repository storage
  can survive server restarts.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias Exdock.Database
  alias Exdock.Database.SchemaHelpers
  alias Exdock.Database.StoredAtom

  @release_page_states [:ok, :not_found, :rate_limit, :unsupported, :error]
  @persisted_fields [:url, :releases_page, :last_check]

  @type t :: %Database.Repository{
          url: String.t(),
          releases_page: atom(),
          last_check: DateTime.t() | nil
        }

  @primary_key {:url, :string, autogenerate: false}
  schema "repositories" do
    field :releases_page, :string
    field :last_check, :utc_datetime
  end

  @spec new(map()) :: t()
  def new(%{url: url, state: state, last_check: %DateTime{} = last_check})
      when is_binary(url) do
    %__MODULE__{
      url: url,
      releases_page: state,
      last_check: last_check
    }
  end

  @spec load_all() :: [t()]
  def load_all do
    Database.Repository
    |> Exdock.Repo.all()
    |> rehydrate_repositories()
  end

  @spec by_url(String.t()) :: t() | nil
  def by_url(url) when is_binary(url) do
    Database.Repository
    |> Exdock.Repo.get_by(url: url)
    |> rehydrate_repository()
  end

  @spec urls() :: [String.t()]
  def urls() do
    from(p in Database.Repository, select: p.url)
    |> Exdock.Repo.all()
  end

  @spec insert(t(), keyword()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def insert(%__MODULE__{} = metadata, opts \\ []) do
    opts = opts |> Keyword.put_new(:on_conflict, :replace_all)

    metadata
    |> repository_changeset(persisted_row(metadata))
    |> Exdock.Repo.insert(opts)
    |> SchemaHelpers.map_ok(&to_runtime_format/1)
  end

  @spec purge() :: {non_neg_integer(), nil | [term()]}
  def purge() do
    Database.Repository
    |> Exdock.Repo.delete_all()
  end

  defp repository_changeset(repository, persisted_row) do
    repository
    |> cast(persisted_row, @persisted_fields)
    |> validate_required([:url, :releases_page, :last_check])
  end

  @spec to_runtime_format(struct()) :: t()
  defp to_runtime_format(%{releases_page: page} = repository_row) do
    # Persisted DB rows keep release states as strings; runtime code expects atoms.
    %{repository_row | releases_page: StoredAtom.load(page, @release_page_states, :error)}
  end

  defp rehydrate_repository(nil), do: nil
  defp rehydrate_repository(%__MODULE__{} = repository_row), do: to_runtime_format(repository_row)
  defp rehydrate_repositories(repository_rows), do: Enum.map(repository_rows, &to_runtime_format/1)

  defp persisted_row(%__MODULE__{url: url, releases_page: releases_page, last_check: last_check}) do
    %{
      "url" => url,
      "releases_page" => StoredAtom.dump(releases_page),
      "last_check" => DateTime.truncate(last_check, :second)
    }
  end
end
