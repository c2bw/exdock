defmodule Exdock.Server.State.Storage.TagsInfo.Change do
  @moduledoc """
  Constructors for tag-info change payloads.
  """

  alias Exdock.Runtime.Mutation
  alias Exdock.Domain

  @doc """
  Update the remote tag information cache.
  """
  @spec tags(list(Domain.TagInfo.t())) :: Mutation.t()
  def tags(list) when is_list(list) do
    Mutation.tags_info!(list)
  end
end
