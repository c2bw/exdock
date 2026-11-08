defmodule Exdock.Server.State.Storage.Persistence.Repository.Mapper do
  @moduledoc """
  Defines the explicit boundary between repository domain values and database
  records.

  Keeping the persisted fields here prevents new runtime-only struct fields
  from being written or compared merely because they were added to a domain
  struct.
  """

  alias Exdock.Database
  alias Exdock.Domain.Repository.{Metadata, Release}

  @spec metadata_record(Metadata.t(), String.t()) :: Database.Repository.t()
  def metadata_record(%Metadata{state: state, last_check: last_check}, url)
      when is_binary(url) do
    Database.Repository.new(%{
      url: url,
      state: state,
      last_check: last_check
    })
  end

  @spec release_record(Release.t()) :: Database.RepositoryRelease.t()
  def release_record(%Release{} = release) do
    release
    |> release_attributes()
    |> Database.RepositoryRelease.new()
  end

  @spec same_release?(Release.t(), Release.t()) :: boolean()
  def same_release?(%Release{} = left, %Release{} = right) do
    Database.RepositoryRelease.same?(release_record(left), release_record(right))
  end

  @spec release_attributes(Release.t()) :: map()
  def release_attributes(%Release{
        source: source,
        repository: repository,
        name: name,
        version: version,
        release_url: release_url,
        compressed_description: compressed_description,
        time_released: time_released
      }) do
    %{
      source: source,
      repository: repository,
      name: name,
      version: version,
      release_url: release_url,
      compressed_description: compressed_description,
      time_released: time_released
    }
  end
end
