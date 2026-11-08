defmodule ExdockWeb.ReleasesLive.Manager.RepositorySourceRow do
  @moduledoc """
  Presentation model for one repository source in the releases manager.

  It owns projection normalization, ordering, and human-readable metadata so
  the component only renders already-prepared rows.
  """

  alias Exdock.Datetime
  alias Exdock.ReadModel.Repository

  @enforce_keys [
    :url,
    :state,
    :release_count,
    :release_count_label,
    :last_check_label,
    :sort_key
  ]
  defstruct [
    :url,
    :state,
    :last_check,
    :release_count,
    :release_count_label,
    :last_check_label,
    :last_check_title,
    :state_label,
    :sort_key
  ]

  @type t :: %__MODULE__{
          url: String.t(),
          state: atom(),
          last_check: DateTime.t() | nil,
          release_count: non_neg_integer(),
          release_count_label: String.t(),
          last_check_label: String.t(),
          last_check_title: String.t() | nil,
          state_label: String.t(),
          sort_key: String.t()
        }

  @spec build_all([Repository.t()], term()) :: [t()]
  def build_all(repositories, clock_now) when is_list(repositories) do
    repositories
    |> Enum.map(&build(&1, clock_now))
    |> Enum.sort_by(& &1.sort_key)
  end

  @spec build(Repository.t(), term()) :: t()
  def build(%Repository{url: url, page: page, releases: releases}, clock_now) do
    last_check = Map.get(page, :last_check)
    state = display_state(Map.get(page, :state, :unknown), last_check)
    release_count = length(releases)

    %__MODULE__{
      url: url,
      state: state,
      last_check: last_check,
      release_count: release_count,
      release_count_label: release_count_label(release_count),
      last_check_label: last_check_label(last_check, clock_now),
      last_check_title: last_check_title(last_check),
      state_label: state_label(state),
      sort_key: url
    }
  end

  defp display_state(_state, nil), do: :unknown
  defp display_state(state, _last_check), do: state

  defp release_count_label(1), do: "1 release"
  defp release_count_label(count), do: "#{count} releases"

  defp last_check_label(nil, _clock_now), do: "Not checked yet"

  defp last_check_label(last_check, clock_now) do
    "Checked #{last_check |> Datetime.utc_to_timezone() |> Datetime.elapsed_since(clock_now)} ago"
  end

  defp last_check_title(nil), do: nil

  defp last_check_title(last_check) do
    last_check
    |> Datetime.utc_to_timezone()
    |> Datetime.prettify()
  end

  defp state_label(:ok), do: "Synced"
  defp state_label(:unknown), do: "Pending"
  defp state_label(:not_found), do: "Not found"
  defp state_label(:rate_limit), do: "Rate limited"
  defp state_label(:unsupported), do: "Unsupported"
  defp state_label(:error), do: "Error"
end
