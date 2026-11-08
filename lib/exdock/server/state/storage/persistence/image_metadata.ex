defmodule Exdock.Server.State.Storage.Persistence.ImageMetadata do
  @moduledoc """
  Repository and mapper for image repository metadata.
  """

  alias Exdock.Database
  alias Exdock.Domain.Image.Metadata

  @spec load(String.t()) :: Metadata.t() | nil
  def load(image_identifier) when is_binary(image_identifier) do
    image_identifier
    |> Metadata.metadata_name()
    |> Database.ImageMetadata.by_name()
    |> from_row()
  end

  @spec load_names([String.t()]) :: %{String.t() => Metadata.t()}
  def load_names(image_identifiers) when is_list(image_identifiers) do
    names =
      image_identifiers
      |> Enum.map(&Metadata.metadata_name/1)
      |> Enum.uniq()

    names
    |> Database.ImageMetadata.load_names()
    |> Map.new(fn %Database.ImageMetadata{name: name} = row ->
      {name, from_row(row)}
    end)
  end

  @spec insert(Metadata.t(), String.t(), keyword()) ::
          {:ok, Database.ImageMetadata.t()} | {:error, Ecto.Changeset.t()}
  def insert(%Metadata{repository_url: repository_url}, image_identifier, opts \\ [])
      when is_binary(image_identifier) do
    %{name: Metadata.metadata_name(image_identifier), repository_url: repository_url}
    |> Database.ImageMetadata.new()
    |> Database.ImageMetadata.insert(Keyword.put_new(opts, :on_conflict, :nothing))
  end

  @spec import(map(), String.t()) ::
          {:ok, Database.ImageMetadata.t()} | {:error, Ecto.Changeset.t()}
  def import(%{} = unsafe, image_identifier)
      when is_binary(image_identifier) and image_identifier != "" do
    unsafe
    |> Metadata.from_import(image_identifier)
    |> insert(image_identifier)
  end

  @spec purge() :: {non_neg_integer(), nil | [term()]}
  def purge, do: Database.ImageMetadata.purge()

  defp from_row(nil), do: nil
  defp from_row(%Database.ImageMetadata{repository_url: repository_url}), do: Metadata.new(repository_url)
end
