defmodule Exdock.Database.RepositoryRelease do
  use Ecto.Schema
  import Ecto.Query
  import Ecto.Changeset
  alias Exdock.Database.SchemaHelpers
  alias Exdock.Database.StoredAtom
  alias Exdock.Database.Compare

  @sources [:github, :gitlab]
  @persisted_fields [:url, :version, :release_url, :source, :name, :description, :time_released]

  @type t :: %Exdock.Database.RepositoryRelease{
          url: String.t(),
          version: String.t(),
          release_url: String.t(),
          source: atom(),
          name: String.t(),
          description: binary(),
          time_released: DateTime.t()
        }

  @primary_key false
  schema "repository_releases" do
    field :url, :string, primary_key: true, autogenerate: false
    field :version, :string, primary_key: true, autogenerate: false
    field :release_url, :string
    field :source, :string
    field :name, :string
    field :description, :binary
    field :time_released, :utc_datetime
  end

  @spec load() :: [t()]
  def load() do
    Exdock.Repo.all(Exdock.Database.RepositoryRelease)
    |> rehydrate_releases()
  end

  @spec load(String.t()) :: [t()]
  def load(repository_url) when is_binary(repository_url) do
    repository_url
    |> query_by_url()
    |> Exdock.Repo.all()
    |> rehydrate_releases()
  end

  @spec new(map()) :: t()
  def new(%{
        repository: repository,
        version: version,
        release_url: release_url,
        source: source,
        name: name,
        compressed_description: compressed_description,
        time_released: time_released
      }) do
    %__MODULE__{
      url: repository,
      version: version,
      release_url: release_url,
      source: source,
      name: name,
      description: compressed_description,
      time_released: time_released |> DateTime.truncate(:second)
    }
  end

  @spec insert(t()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def insert(%__MODULE__{} = release, opts \\ []) do
    opts = opts |> Keyword.put_new(:on_conflict, :replace_all)

    release
    |> release_changeset(persisted_row(release))
    |> Exdock.Repo.insert(opts)
    |> SchemaHelpers.map_ok(&to_runtime_format/1)
  end

  @doc """
    Return whether two releases are the same or not.
  """
  @spec same?(t(), t()) :: boolean()
  def same?(%__MODULE__{time_released: a_date} = a, %__MODULE__{time_released: b_date} = b) do
    Compare.compare(
      %{a | time_released: a_date |> DateTime.truncate(:second)},
      %{b | time_released: b_date |> DateTime.truncate(:second)}
    )
  end

  # Keep provider enums as atoms in runtime while persisting them as strings.
  defp to_runtime_format(%{source: source} = release_row) do
    %{release_row | source: StoredAtom.load(source, @sources, :github)}
  end

  defp rehydrate_releases(releases), do: Enum.map(releases, &to_runtime_format/1)

  defp query_by_url(url) when is_binary(url) do
    from(r in Exdock.Database.RepositoryRelease, select: r, where: r.url == ^url)
  end

  defp persisted_row(%__MODULE__{
         url: url,
         version: version,
         release_url: release_url,
         source: source,
         name: name,
         description: description,
         time_released: time_released
       }) do
    %{
      "url" => url,
      "version" => version,
      "release_url" => release_url,
      "source" => StoredAtom.dump(source),
      "name" => name,
      "description" => description,
      "time_released" => DateTime.truncate(time_released, :second)
    }
  end

  defp release_changeset(release, persisted_release) do
    release
    |> cast(persisted_release, @persisted_fields)
    |> validate_required([:url, :version, :release_url, :source, :name])
  end
end
