defmodule Exdock.Domain.Repository do
  @moduledoc """
  Repository data retrieved from services.

  ## Fields
  - `url`
  - `metadata`: stores the repository state and check time
  - `releases`: list of releases for the repository
  """
  alias Exdock.Domain.Repository

  defstruct [
    :url,
    :metadata,
    :releases
  ]

  @type t :: %__MODULE__{
          url: String.t(),
          metadata: Repository.Metadata.t(),
          releases: list(Repository.Release.t())
        }

  @spec default(String.t()) :: t()
  def default(url) when is_binary(url) do
    %__MODULE__{
      url: url,
      metadata: Repository.Metadata.default(),
      releases: []
    }
  end

  @doc """
  Update the metadata for the repository.
  Sets the check time to now and the state to the passed state.
  """
  @spec with_metadata_state(t(), Repository.Metadata.page_state(), DateTime.t()) :: t()
  def with_metadata_state(
        %__MODULE__{metadata: %Repository.Metadata{} = metadata} = repository,
        state,
        checked_at \\ DateTime.utc_now()
      )
      when is_atom(state) do
    updated_metadata =
      metadata
      |> Repository.Metadata.set_last_check(checked_at)
      |> Repository.Metadata.set_state(state)

    %{repository | metadata: updated_metadata}
  end

  @doc """
  Replace a release with the same version and keep releases newest-first.
  """
  @spec put_release(t(), Repository.Release.t()) :: t()
  def put_release(%__MODULE__{releases: releases} = repository, %Repository.Release{} = release) do
    {_stored_release, remaining_releases} = pop_matching_release(releases, release)

    %__MODULE__{repository | releases: [release | remaining_releases]}
    |> sort_releases_by_time()
  end

  @doc false
  @spec matching_release(t(), Repository.Release.t()) :: Repository.Release.t() | nil
  def matching_release(%__MODULE__{releases: releases}, %Repository.Release{} = release) do
    {stored_release, _remaining_releases} = pop_matching_release(releases, release)
    stored_release
  end

  defp pop_matching_release(releases, %Repository.Release{} = release) when is_list(releases) do
    # Persistence is keyed by release version. Split the previous version out
    # once so the caller can decide whether to insert or compare-and-update.
    Enum.reduce(releases, {nil, []}, fn
      stored_release, {nil, rest} ->
        if Repository.Release.same_version(stored_release, release) do
          {stored_release, rest}
        else
          {nil, [stored_release | rest]}
        end

      stored_release, {matched_release, rest} ->
        {matched_release, [stored_release | rest]}
    end)
    |> then(fn {matched_release, rest} -> {matched_release, Enum.reverse(rest)} end)
  end

  # Persistence is keyed by release version, while consumers read the in-memory
  # aggregate newest-first. Re-sort after every upsert so both code paths agree.
  defp sort_releases_by_time(%__MODULE__{releases: releases} = repository) do
    releases = Enum.sort_by(releases, & &1.time_released, {:desc, DateTime})
    %{repository | releases: releases}
  end
end
