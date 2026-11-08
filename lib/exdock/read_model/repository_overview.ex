defmodule Exdock.ReadModel.RepositoryOverview do
  @moduledoc """
  Derived release-overview data consumed by the releases LiveView.
  """

  alias Exdock.ReadModel.{Release, Repository, RepositoryPage}

  @states [:unknown, :ok, :not_found, :rate_limit, :unsupported, :error]

  defstruct previews: [],
            page_counts: %{
              unknown: 0,
              ok: 0,
              not_found: 0,
              rate_limit: 0,
              unsupported: 0,
              error: 0
            },
            total_release_count: 0

  @type preview :: {RepositoryPage.t(), Release.t(), non_neg_integer()}
  @type t :: %__MODULE__{
          previews: [preview()],
          page_counts: %{required(RepositoryPage.state()) => non_neg_integer()},
          total_release_count: non_neg_integer()
        }

  @spec from_repositories([Repository.t()]) :: t()
  def from_repositories(repositories) when is_list(repositories) do
    %__MODULE__{
      previews: previews(repositories),
      page_counts: page_counts(repositories),
      total_release_count: Enum.sum(Enum.map(repositories, &length(&1.releases)))
    }
  end

  defp previews(repositories) do
    repositories
    |> Enum.flat_map(fn %Repository{page: page, releases: releases} ->
      case List.first(releases) do
        %Release{} = release -> [{page, release, length(releases)}]
        nil -> []
      end
    end)
    |> Enum.sort_by(fn {_page, release, _count} -> release.time_released end, {:desc, DateTime})
  end

  defp page_counts(repositories) do
    Enum.reduce(repositories, empty_page_counts(), fn %Repository{page: page}, counts ->
      Map.update!(counts, page_state(page), &(&1 + 1))
    end)
  end

  defp page_state(%RepositoryPage{last_check: nil}), do: :unknown
  defp page_state(%RepositoryPage{state: state}) when state in @states, do: state

  defp empty_page_counts, do: Map.new(@states, &{&1, 0})
end
