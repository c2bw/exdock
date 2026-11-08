defmodule Exdock.Server.State do
  @moduledoc """
  In-memory state container for the Exdock server process.

  The state groups persisted settings, the live cluster snapshot, repository/tag
  metadata, logging data, and the periodic automation scheduler. Storage modules
  own the details of each domain; this module coordinates creation and shared
  broadcast helpers.
  """

  alias Exdock.Server.State
  alias Exdock.Server.State.Change.Outcome
  alias Exdock.Runtime.DomainCatalog
  alias Exdock.Runtime.Mutation
  alias Exdock.Server.Broadcast
  alias Exdock.Server.State.PeriodicJob
  alias Exdock.Server.State.Storage
  alias Exdock.Server.State.Storage.Persistence.Node, as: NodePersistence
  alias Exdock.Server.State.Effects

  defstruct [
    :revision,
    :settings,
    :cluster,
    :tags,
    :repositories,
    :periodic_job,
    refresh_generations: %{}
  ]

  @type t :: %__MODULE__{
          revision: non_neg_integer(),
          settings: Storage.Settings.t(),
          cluster: Storage.Cluster.t(),
          tags: Storage.TagsInfo.t(),
          repositories: Storage.Repositories.t(),
          periodic_job: State.PeriodicJob.t(),
          refresh_generations: %{optional(String.t()) => pos_integer()}
        }

  @doc """
    Create the initial state expected by `Exdock.Server`.

    Persisted settings, tags, and repositories are loaded here; live cluster data
    starts empty and is populated as nodes connect or refresh jobs complete.
  """
  @spec create() :: t()
  def create() do
    settings = Storage.Settings.load()
    periodic_job = PeriodicJob.create(Storage.Settings.get(settings).cron_string)

    %__MODULE__{
      revision: 0,
      settings: settings,
      cluster: Storage.Cluster.new(),
      tags: Storage.TagsInfo.load(),
      repositories: Storage.Repositories.load(),
      periodic_job: periodic_job
    }
  end

  @spec periodic_job_rollover(t()) :: t()
  def periodic_job_rollover(%__MODULE__{periodic_job: periodic_job} = state) do
    state
    |> Map.put(:periodic_job, PeriodicJob.set_next(periodic_job))
    |> bump_revision()
  end

  @spec bump_revision(t()) :: t()
  def bump_revision(%__MODULE__{revision: revision} = state) do
    %{state | revision: (revision || 0) + 1}
  end

  @doc """
    Add a node to the state from persisted storage and describe its broadcasts.

    Live Docker data is refreshed separately by the caller through a node refresh
    job, so this function only establishes the node as present.
  """
  @spec nodeup(t(), String.t(), map()) :: State.Transition.result()
  def nodeup(%__MODULE__{cluster: cluster} = state, node, metadata)
      when is_binary(node) and is_map(metadata) do
    case Storage.Cluster.load(cluster, node, metadata) do
      {:ok, cluster} ->
        state = %{state | cluster: cluster} |> bump_revision()
        Outcome.new(state, cluster_broadcast_effects())

      {:error, reason} ->
        # Persistence is a warm-start cache. Keep the connected node addressable
        # so a live refresh can repair a damaged or unavailable saved snapshot.
        node_data =
          (Storage.Nodes.get(cluster.storage, node) || NodePersistence.load(node) || Exdock.Domain.Node.default(node))
          |> Exdock.Domain.Node.put_metadata(metadata)

        storage = Storage.Nodes.set(cluster.storage, node, node_data)
        state = %{state | cluster: %{cluster | storage: storage}} |> bump_revision()
        Outcome.new(state, [{:log, :error, "Unable to hydrate node: #{inspect(reason)}"} | cluster_broadcast_effects()])
    end
  end

  @doc """
    Remove a node from the cluster and broadcast dependent views.

    Repository state is rebroadcast because availability and release status can
    depend on the set of online nodes.
  """
  @spec nodedown(t(), String.t()) :: {t(), [Exdock.Server.State.Effects.effect()]}
  def nodedown(%__MODULE__{cluster: cluster} = state, node) when is_binary(node) do
    cluster = cluster |> Storage.Cluster.remove(node)
    state = %{state | cluster: cluster} |> bump_revision()
    {state, broadcast_effects(DomainCatalog.cluster_snapshot_domains())}
  end

  @doc """
  Broadcast data through the shared batching process.

  Nil data is ignored. Non-nil data defaults to a short delayed broadcast so
  repeated state changes can collapse into a single UI update.
  """
  @spec broadcast_helper(Mutation.domain(), any(), keyword()) :: :ok
  def broadcast_helper(domain, nil, _opts) when is_atom(domain), do: :ok

  def broadcast_helper(domain, data, opts) when is_atom(domain) do
    true = Mutation.valid_domain?(domain)
    opts = opts |> Keyword.put_new(:delayed, true) |> Keyword.put_new(:delay_ms, 30)
    :ok = Broadcast.broadcast(domain, data, opts)
  end

  defp cluster_broadcast_effects do
    broadcast_effects(DomainCatalog.cluster_domains())
  end

  defp broadcast_effects(domains), do: Effects.broadcasts(domains)
end
