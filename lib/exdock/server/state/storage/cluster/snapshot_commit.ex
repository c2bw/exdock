defmodule Exdock.Server.State.Storage.Cluster.SnapshotCommit do
  @moduledoc """
  Commits one node snapshot as a single reconciliation boundary.

  The returned projection is safe to publish only after its durable delta has
  committed. Persistence failures leave the caller's previous projection
  untouched.
  """

  alias Exdock.Protocol.Snapshot, as: Client
  alias Exdock.Server.State.Storage
  alias Exdock.Server.State.Storage.Cluster.{Persistence, Reconciliation}
  alias Exdock.Server.State.Storage.Cluster.Persistence.Plan
  alias Exdock.Server.State.Storage.Cluster.Utils.NodeStorage

  @enforce_keys [:projection, :persistence_plan]
  defstruct [:projection, :persistence_plan]

  @type cluster_projection :: %{
          required(:storage) => NodeStorage.t(),
          optional(any()) => any()
        }

  @type t :: %__MODULE__{
          projection: cluster_projection(),
          persistence_plan: Plan.t()
        }

  @spec commit(
          cluster_projection(),
          String.t(),
          [Client.Container.t()],
          [Client.Image.t()],
          Storage.TagsInfo.t(),
          DateTime.t()
        ) :: {:ok, cluster_projection()} | {:error, term()}
  def commit(
        %{storage: %NodeStorage{}} = previous,
        node,
        containers,
        images,
        %Storage.TagsInfo{} = tags_info,
        %DateTime{} = fetched_at
      )
      when is_binary(node) and is_list(containers) and is_list(images) do
    previous
    |> prepare(node, containers, images, tags_info, fetched_at)
    |> commit()
  end

  @doc "Builds the reconciled projection and its durable delta without performing I/O."
  @spec prepare(
          cluster_projection(),
          String.t(),
          [Client.Container.t()],
          [Client.Image.t()],
          Storage.TagsInfo.t(),
          DateTime.t()
        ) :: t()
  @spec prepare(
          cluster_projection(),
          String.t(),
          [Client.Container.t()],
          [Client.Image.t()],
          Storage.TagsInfo.t(),
          DateTime.t(),
          keyword()
        ) :: t()
  def prepare(
        %{storage: %NodeStorage{}} = previous,
        node,
        containers,
        images,
        %Storage.TagsInfo{} = tags_info,
        %DateTime{} = fetched_at,
        opts \\ []
      )
      when is_binary(node) and is_list(containers) and is_list(images) do
    projection = Reconciliation.reconcile(previous, node, containers, images, tags_info, fetched_at, opts)

    %__MODULE__{
      projection: projection,
      persistence_plan: Plan.build(previous, projection, node)
    }
  end

  @doc "Persists a prepared snapshot and releases its projection on success."
  @spec commit(t()) :: {:ok, cluster_projection()} | {:error, term()}
  def commit(%__MODULE__{projection: projection, persistence_plan: persistence_plan}) do
    case Persistence.persist(persistence_plan) do
      {:ok, %Plan{}} -> {:ok, projection}
      {:error, reason} -> {:error, reason}
    end
  end
end
