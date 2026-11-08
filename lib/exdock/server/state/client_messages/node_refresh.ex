defmodule Exdock.Server.State.ClientMessages.NodeRefresh do
  @moduledoc false

  alias Exdock.Protocol.Messages
  alias Exdock.Runtime.DomainCatalog
  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.Job
  alias Exdock.Server.Jobs.NodeRefreshSnapshot
  alias Exdock.Server.Jobs.Result
  alias Exdock.Server.State
  alias Exdock.Server.State.ContainerStatus
  alias Exdock.Server.State.ClientMessages.NodeRefresh.Prepared
  alias Exdock.Server.State.Effects
  alias Exdock.Server.State.Effects.Plan, as: EffectPlan
  alias Exdock.Server.State.Storage
  alias Exdock.Server.State.Storage.Cluster
  alias Exdock.Server.State.Storage.Cluster.SnapshotCommit

  @spec reduce(State.t(), Messages.JobResult.t(), DateTime.t()) ::
          Prepared.t()
  def reduce(
        %State{cluster: %Cluster{} = cluster, tags: %Storage.TagsInfo{} = tags} =
          state,
        %Messages.JobResult{
          job: %Job{name: :node_refresh, id: job_id, refresh_generation: generation},
          result: %Result{
            node: node,
            data: {container_results, image_results},
            error: nil
          }
        },
        %DateTime{} = occurred_at
      ) do
    refresh_snapshot = NodeRefreshSnapshot.new(container_results, image_results)

    if generation != nil and generation <= Map.get(state.refresh_generations, node, 0) do
      # Complete the old job, but never publish or persist its superseded facts.
      Prepared.immediate(state, [publish_update(job_id, node, refresh_snapshot)])
    else
      prepared = prepare(state, cluster, tags, job_id, node, refresh_snapshot, occurred_at)
      updated_state = prepared.updated_state

      generations =
        if generation == nil, do: state.refresh_generations, else: Map.put(state.refresh_generations, node, generation)

      %{prepared | updated_state: %{updated_state | refresh_generations: generations}}
    end
  end

  def reduce(
        %State{} = state,
        %Messages.JobResult{
          job: %Job{name: :node_refresh, id: job_id},
          result: %Result{node: node, error: error}
        },
        %DateTime{}
      )
      when not is_nil(error) do
    effects = [
      log(:error, "Error refreshing node [#{node}]: #{inspect(error)}"),
      job_update(job_id, node, %{}, error)
    ]

    Prepared.immediate(state, effects)
  end

  defp prepare(
         %State{} = state,
         %Cluster{} = cluster,
         %Storage.TagsInfo{} = tags,
         job_id,
         node,
         refresh_snapshot,
         occurred_at
       ) do
    refresh_log_effects = log_refresh_errors(node, refresh_snapshot)

    snapshot_commit =
      SnapshotCommit.prepare(
        cluster,
        node,
        NodeRefreshSnapshot.containers(refresh_snapshot),
        NodeRefreshSnapshot.images(refresh_snapshot),
        tags,
        occurred_at,
        preserve_containers: failed_container_names(refresh_snapshot),
        preserve_images: failed_image_ids(refresh_snapshot)
      )

    updated_state = %{state | cluster: snapshot_commit.projection} |> State.bump_revision()
    state_effects = Effects.broadcasts(DomainCatalog.cluster_snapshot_domains())

    effects =
      EffectPlan.new(
        before_publication: refresh_log_effects,
        status_changes: container_status_effects(state, updated_state),
        publications: [publish_update(job_id, node, refresh_snapshot)],
        derived_publications: state_effects
      )
      |> EffectPlan.effects()

    Prepared.persisted(
      state,
      updated_state,
      snapshot_commit,
      effects,
      refresh_log_effects,
      job_id,
      node
    )
  end

  defp failed_container_names(snapshot) do
    Enum.flat_map(NodeRefreshSnapshot.container_errors(snapshot), fn
      {_error, %{name: name}} when is_binary(name) -> [name]
      _unknown -> []
    end)
  end

  defp failed_image_ids(snapshot) do
    Enum.flat_map(NodeRefreshSnapshot.image_errors(snapshot), fn
      {_error, id} when is_binary(id) -> [id]
      {_error, %{id: id}} when is_binary(id) -> [id]
      _unknown -> []
    end)
  end

  defp log_refresh_errors(node, %NodeRefreshSnapshot{} = snapshot) do
    [
      {NodeRefreshSnapshot.container_errors(snapshot), "container"},
      {NodeRefreshSnapshot.image_errors(snapshot), "image"}
    ]
    |> Enum.flat_map(fn {errors, noun} ->
      maybe_log_refresh_errors(node, errors, noun)
    end)
  end

  defp publish_update(job_id, node, %NodeRefreshSnapshot{} = snapshot) do
    error =
      if NodeRefreshSnapshot.container_errors(snapshot) != [] or NodeRefreshSnapshot.image_errors(snapshot) != [],
        do: :partial_refresh

    job_update(job_id, node, snapshot, error)
  end

  defp maybe_log_refresh_errors(_node, [], _noun), do: []

  defp maybe_log_refresh_errors(node, errors, noun) do
    [
      log(
        :warning,
        "Node [#{node}]: #{inspect(length(errors))} errored #{noun}s"
      )
    ]
  end

  defp job_update(job_id, node, update, error) do
    {:job_update, Jobs.Update.new(job_id, node, update, true, error)}
  end

  defp container_status_effects(before_state, after_state) do
    before_state
    |> ContainerStatus.transitions(after_state)
    |> Enum.map(&{:container_status, &1})
  end

  defp log(level, message), do: {:log, level, message}
end
