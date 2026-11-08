defmodule Exdock.Server.State.Storage.Repositories.Change do
  @moduledoc """
  Constructors for repository storage change payloads.
  """

  alias Exdock.Runtime.Mutation
  alias Exdock.Server.State.Storage.Repositories

  @doc """
  Apply fetched release results to their repositories.
  """
  @spec releases([Repositories.raw_fetch_result()]) :: Mutation.t()
  def releases(results) when is_list(results) do
    Mutation.repository_releases!(results)
  end
end
