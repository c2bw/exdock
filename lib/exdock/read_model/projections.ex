defmodule Exdock.ReadModel.Projections do
  @moduledoc """
  Registry for page-level read projections and their runtime event sources.

  Query validation, LiveView assigns, and initial event revisions all consume
  this registry so adding a projection does not require parallel key lists.
  """

  alias Exdock.ReadModel.Projections.{ClusterInfo, Containers, Images, Nodes, Repositories}
  alias Exdock.Runtime.EventCatalog

  @specs %{
    nodes: %{module: Nodes, assigns: [:nodes], sources: [:nodes]},
    containers: %{
      module: Containers,
      assigns: [:containers, :containers_extended],
      sources: [:containers]
    },
    images: %{module: Images, assigns: [:images], sources: [:images]},
    repositories: %{
      module: Repositories,
      assigns: [:repositories],
      sources: [:repositories]
    },
    cluster_info: %{
      module: ClusterInfo,
      assigns: [:cluster_info],
      sources: [:cluster_info]
    }
  }
  @projection_source_modules Enum.reduce(@specs, %{}, fn {_key, spec}, modules ->
                               Map.merge(
                                 modules,
                                 Map.new(spec.sources, &{&1, spec.module})
                               )
                             end)
  @base_broadcast_sources EventCatalog.sources_for_consumer(:assigns) --
                            Map.keys(@projection_source_modules)
  @type key :: :nodes | :containers | :images | :repositories | :cluster_info
  @type revision_source :: EventCatalog.source()
  @type topic :: EventCatalog.topic()

  @spec keys() :: [key()]
  def keys, do: Map.keys(@specs)

  @spec valid_keys?([term()]) :: boolean()
  def valid_keys?(keys) when is_list(keys), do: Enum.all?(keys, &Map.has_key?(@specs, &1))

  @spec unknown_keys([term()]) :: [term()]
  def unknown_keys(keys) when is_list(keys), do: Enum.reject(keys, &Map.has_key?(@specs, &1))

  @spec assigns([key()]) :: [atom()]
  def assigns(keys) when is_list(keys) do
    Enum.flat_map(keys, fn key ->
      @specs
      |> Map.fetch!(key)
      |> Map.fetch!(:assigns)
    end)
  end

  @spec module_for(key()) :: module()
  def module_for(key), do: @specs |> Map.fetch!(key) |> Map.fetch!(:module)

  @spec query_assigns(key(), term()) :: map()
  def query_assigns(key, input), do: module_for(key).from_query(input)

  @spec topics([key()]) :: [topic()]
  def topics(keys) when is_list(keys) do
    keys
    |> Enum.flat_map(fn key -> @specs |> Map.fetch!(key) |> Map.fetch!(:sources) end)
    |> Enum.map(&EventCatalog.topic_for_source!/1)
    |> Enum.uniq()
  end

  @spec topic_for_source(term()) :: {:ok, topic()} | :error
  defdelegate topic_for_source(source), to: EventCatalog

  @spec topic_for_source!(atom()) :: topic()
  defdelegate topic_for_source!(source), to: EventCatalog

  @spec known_source?(term()) :: boolean()
  defdelegate known_source?(source), to: EventCatalog

  @spec sources() :: [atom()]
  defdelegate sources(), to: EventCatalog

  @doc false
  @spec handled_sources() :: [EventCatalog.source()]
  def handled_sources,
    do: Map.keys(@projection_source_modules) ++ @base_broadcast_sources

  @spec initial_revisions(non_neg_integer(), non_neg_integer()) :: %{
          revision_source() => non_neg_integer()
        }
  def initial_revisions(runtime_revision, activity_revision)
      when is_integer(runtime_revision) and runtime_revision >= 0 and
             is_integer(activity_revision) and activity_revision >= 0 do
    EventCatalog.sources_for_revision(:runtime)
    |> Map.new(&{&1, runtime_revision})
    |> Map.merge(Map.new(EventCatalog.sources_for_revision(:activity), &{&1, activity_revision}))
  end

  @doc """
  Normalizes one runtime event payload into the page assigns it replaces.

  Sources with derived assigns, such as nodes and containers, are expanded here
  so initial query projections and subsequent broadcasts share one contract.
  """
  @spec broadcast_assigns(atom(), term()) :: {:ok, map()} | :ignored | :unknown
  def broadcast_assigns(source, payload) when is_atom(source) do
    case Map.fetch(@projection_source_modules, source) do
      {:ok, module} -> {:ok, module.from_broadcast(payload)}
      :error -> broadcast_assigns_without_projection(source, payload)
    end
  end

  defp broadcast_assigns_without_projection(source, payload) do
    case base_broadcast_assigns(source, payload) do
      :unknown -> intentionally_ignored_or_unknown(source)
      result -> result
    end
  end

  defp intentionally_ignored_or_unknown(source) do
    case EventCatalog.consumer_policy_for(source) do
      {:ok, :routing_only} -> :ignored
      _policy -> :unknown
    end
  end

  defp base_broadcast_assigns(:settings, user_settings),
    do: {:ok, %{user_settings: user_settings}}

  defp base_broadcast_assigns(:server_configuration, configuration),
    do: {:ok, %{server_configuration: configuration}}

  defp base_broadcast_assigns(:status, status), do: {:ok, %{status: status}}
  defp base_broadcast_assigns(:log, log), do: {:ok, %{log: log}}
  defp base_broadcast_assigns(_source, _payload), do: :unknown
end
