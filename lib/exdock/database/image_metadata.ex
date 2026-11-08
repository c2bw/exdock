defmodule Exdock.Database.ImageMetadata do
  use Ecto.Schema
  import Ecto.Query
  import Ecto.Changeset

  @type t :: %Exdock.Database.ImageMetadata{
          name: String.t(),
          repository_url: String.t()
        }

  @primary_key {:name, :string, autogenerate: false}
  schema "image_metadata" do
    field(:repository_url, :string)
  end

  @spec new(map()) :: t()
  def new(%{repository_url: repository_url, name: name})
      when is_binary(repository_url) and is_binary(name) do
    %__MODULE__{name: name, repository_url: repository_url}
  end

  @doc """
    Load all the image metadata from the database.
  """
  @spec load_all() :: [t()]
  def load_all do
    from(i in Exdock.Database.ImageMetadata, select: i)
    |> Exdock.Repo.all()
  end

  @doc """
  Loads metadata for the requested image names.
  """
  @spec load_names([String.t()]) :: [t()]
  def load_names(names) when is_list(names) do
    from(i in Exdock.Database.ImageMetadata, where: i.name in ^names)
    |> Exdock.Repo.all()
  end

  @doc """
    Retrieve the image metadata by its name
  """
  @spec by_name(String.t()) :: t() | nil
  def by_name(name) when is_binary(name) do
    Exdock.Repo.get_by(Exdock.Database.ImageMetadata, name: name)
  end

  @doc """
    Insert the image metadata into the database.
  """
  @spec insert(t(), keyword()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def insert(%__MODULE__{} = image_metadata, opts \\ []) do
    opts = opts |> Keyword.put_new(:on_conflict, :nothing)

    image_metadata
    |> changeset(%{})
    |> Exdock.Repo.insert(opts)
  end

  @doc """
    Removes all metadata of images.
  """
  @spec purge() :: {non_neg_integer(), nil | [term()]}
  def purge() do
    Exdock.Database.ImageMetadata
    |> Exdock.Repo.delete_all()
  end

  defp changeset(struct, params) do
    struct
    |> cast(params, [:name, :repository_url])
    |> validate_required([:name, :repository_url])
  end
end
