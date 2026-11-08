defmodule Exdock.ReadModel do
  @moduledoc """
  Explicit read-only projections of Exdock's authoritative runtime state.

  Named queries replace executable callbacks. Page projections are assembled in
  one call so every returned value comes from the same runtime revision.
  """

  alias Exdock.NodeId
  alias Exdock.ReadModel.{PageSnapshot, Repository, RepositoryOverview}

  @type projection :: :nodes | :containers | :images | :repositories | :cluster_info

  @spec page([projection()]) :: Exdock.ReadModel.Page.t()
  def page(projections) when is_list(projections) do
    projections
    |> PageSnapshot.build()
    |> then(&struct!(Exdock.ReadModel.Page, &1))
  end

  @doc "Returns a page shell and node detail captured from one runtime revision."
  @spec node_page(String.t(), [projection()]) ::
          {Exdock.ReadModel.Page.t(), Exdock.ReadModel.Node.t() | :not_found}
  def node_page(node_id, projections) when is_binary(node_id) and is_list(projections) do
    case NodeId.validate(node_id) do
      :ok ->
        {page, node_detail} = PageSnapshot.build_node(node_id, projections)
        {struct!(Exdock.ReadModel.Page, page), node_detail}

      {:error, _reason} ->
        {page(projections), :not_found}
    end
  end

  @spec repository_data([Repository.t()], String.t()) :: Repository.t()
  def repository_data(repositories, repository_url)
      when is_list(repositories) and is_binary(repository_url) do
    Enum.find(repositories, &(&1.url == repository_url)) ||
      Repository.default(repository_url)
  end

  @spec repository_overview([Repository.t()]) :: RepositoryOverview.t()
  def repository_overview(repositories) when is_list(repositories),
    do: RepositoryOverview.from_repositories(repositories)
end
