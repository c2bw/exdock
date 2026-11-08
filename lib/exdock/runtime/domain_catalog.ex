defmodule Exdock.Runtime.DomainCatalog do
  @moduledoc """
  Canonical metadata for authoritative runtime domains.

  Keeping this catalog and its mutation contract independent from server state
  structs lets mutation validation, reload planning, node lifecycle broadcasts,
  and derived projection invalidation share one vocabulary without introducing
  compile cycles.
  """

  alias Exdock.Runtime.MutationContract

  @cluster_domains [:nodes, :images, :containers]
  @cluster_snapshot_domains @cluster_domains ++ [:repositories]

  @dependencies %{
    settings: [],
    tags: [],
    repositories: [],
    nodes: [:settings],
    images: [:settings],
    containers: [:settings, :images, :tags]
  }

  @derived_projection_sources %{
    cluster_info: @cluster_domains,
    server_configuration: [:settings | @cluster_domains]
  }

  @type domain :: MutationContract.domain()
  @type action :: MutationContract.action()
  @type derived_projection :: :cluster_info | :server_configuration

  @spec domains() :: [domain()]
  defdelegate domains(), to: MutationContract

  @spec valid?(term()) :: boolean()
  defdelegate valid?(domain), to: MutationContract, as: :valid_domain?

  @spec actions(domain()) :: [action()]
  defdelegate actions(domain), to: MutationContract

  @spec valid_action?(term(), term()) :: boolean()
  defdelegate valid_action?(domain, action), to: MutationContract

  @spec cluster_domains() :: [domain()]
  def cluster_domains, do: @cluster_domains

  @doc "Domains whose public projections change when a node snapshot is replaced or removed."
  @spec cluster_snapshot_domains() :: [domain()]
  def cluster_snapshot_domains, do: @cluster_snapshot_domains

  @spec dependents(domain(), atom()) :: [domain()]
  def dependents(:settings, :user_setting), do: []

  def dependents(changed_domain, _action) do
    domains()
    |> Enum.reject(&(&1 == changed_domain))
    |> Enum.filter(&depends_on_transitively?(&1, changed_domain, MapSet.new()))
  end

  @spec derived_projections(Enumerable.t()) :: [derived_projection()]
  def derived_projections(changed_domains) do
    changed_domains = MapSet.new(changed_domains)

    @derived_projection_sources
    |> Enum.filter(fn {_projection, sources} ->
      Enum.any?(sources, &MapSet.member?(changed_domains, &1))
    end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort()
  end

  defp depends_on_transitively?(domain, dependency, _visited) when domain == dependency, do: true

  defp depends_on_transitively?(domain, dependency, visited) do
    if MapSet.member?(visited, domain) do
      false
    else
      visited = MapSet.put(visited, domain)

      @dependencies
      |> Map.fetch!(domain)
      |> Enum.any?(&depends_on_transitively?(&1, dependency, visited))
    end
  end
end
