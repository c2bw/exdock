defmodule Exdock.Server.Jobs.Client.Container do
  @moduledoc """
  Builds remote container jobs from the current server state.

  These functions validate that the requested container still exists in the
  latest cluster snapshot, attach UI/logging metadata to the job, and return a
  deferred payload for the job dispatcher.
  """

  alias Exdock.Container.Policy
  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.Detail
  alias Exdock.Server.Jobs.Payload.ContainerAction
  alias Exdock.Server.Jobs.Spec
  alias Exdock.Server.State
  alias Exdock.Server.State.Storage
  alias Exdock.Domain

  @doc """
  Recreate a container.

  If `pull` is true, it will pull the image before recreating the container.
  """
  @spec recreate(State.t(), list(tuple()), boolean()) :: Jobs.Detail.t() | Jobs.Package.t() | nil
  def recreate(%State{cluster: %Storage.Cluster{storage: storage}}, jobs, pull) when is_list(jobs) and is_boolean(pull) do
    storage
    |> collect_recreatable_containers(jobs)
    |> build_recreate_work(pull)
  end

  defp build_recreate_work([], _pull), do: nil

  defp build_recreate_work(containers, pull) when is_list(containers) and is_boolean(pull) do
    containers
    |> Enum.map(&recreate_work_group(&1, pull))
    |> finish_recreate_work(containers, pull)
  end

  defp collect_recreatable_containers(storage, jobs) when is_list(jobs) do
    # Keep only containers allowed by the recreate blacklist and still present in
    # the current snapshot.
    Enum.flat_map(jobs, &load_recreate_container_candidate(storage, &1))
  end

  defp finish_recreate_work([single_work_group], _containers, _pull), do: single_work_group

  defp finish_recreate_work(work_groups, containers, pull)
       when is_list(work_groups) and is_list(containers) and is_boolean(pull) do
    build_recreate_package(work_groups, containers, pull)
  end

  defp load_recreate_container_candidate(storage, {node, name})
       when is_binary(node) and is_binary(name) do
    with %Domain.Container{} = container <- Storage.Containers.get_container(storage, node, name, :name),
         true <- Policy.recreatable?(name, container.core) do
      [container]
    else
      _ -> []
    end
  end

  defp build_recreate_package(work_groups, containers, pull)
       when is_list(work_groups) and is_list(containers) and is_boolean(pull) do
    details = Enum.flat_map(work_groups, &List.wrap/1)
    Jobs.Package.new(:container_recreate, details, recreate_package_metadata(containers, pull))
  end

  # Log metadata tracks the selected container set as presented to callers, while
  # detail execution is flattened for scheduling.
  defp recreate_package_metadata(containers, pull) when is_list(containers) and is_boolean(pull) do
    names = Enum.map(containers, & &1.name)
    {length(names), names, pull}
  end

  @spec recreate_work_group(Domain.Container.t(), boolean()) :: Jobs.Detail.t() | [Jobs.Detail.t()]
  defp recreate_work_group(%Domain.Container{node: node, name: name}, false = _pull_image) do
    remote_detail(:container_recreate, node, [name, false], ContainerAction.new(node, name))
  end

  defp recreate_work_group(%Domain.Container{} = container, true = _pull_image) do
    pull_detail = recreate_pull_detail(container)
    recreate_detail = recreate_work_group(container, false)

    # Pull is launched first; recreate waits on pull success via this dependency.
    [pull_detail, Detail.chain_to(recreate_detail, pull_detail)]
  end

  @spec start(State.t(), String.t(), String.t()) :: Jobs.Detail.t() | nil
  def start(%State{cluster: %Storage.Cluster{storage: storage}}, node, name) do
    container_action_work(storage, node, name, :container_start)
  end

  @spec stop(State.t(), String.t(), String.t()) :: Jobs.Detail.t() | nil
  def stop(%State{cluster: %Storage.Cluster{storage: storage}}, node, name) do
    container_action_work(storage, node, name, :container_stop)
  end

  @spec restart(State.t(), String.t(), String.t()) :: Jobs.Detail.t() | nil
  def restart(%State{cluster: %Storage.Cluster{storage: storage}}, node, name) do
    container_action_work(storage, node, name, :container_restart)
  end

  @spec logs(State.t(), String.t(), String.t()) :: Jobs.Detail.t() | nil
  def logs(%State{cluster: %Storage.Cluster{storage: storage}}, node, name) do
    container_action_work(storage, node, name, :container_logs)
  end

  defp container_action_work(storage, node, name, job_name)
       when is_binary(node) and is_binary(name) and
              job_name in [:container_start, :container_stop, :container_restart, :container_logs] do
    storage
    |> Storage.Containers.get_container(node, name, :name)
    |> build_container_action_work(job_name)
  end

  defp build_container_action_work(nil, job_name) when is_atom(job_name), do: nil

  defp build_container_action_work(%Domain.Container{} = container, job_name) when is_atom(job_name),
    do: build_container_action_detail(container, job_name)

  defp recreate_pull_detail(%Domain.Container{node: node} = container)
       when is_binary(node) do
    tag = Domain.Container.image_tag(container)
    Jobs.Client.Image.do_pull(node, tag)
  end

  defp build_container_action_detail(%Domain.Container{id: id, node: node, name: name}, :container_logs),
    do: remote_detail(:container_logs, node, [id, []], container_job_data(node, name))

  defp build_container_action_detail(%Domain.Container{node: node, name: name}, action)
       when action in [:container_start, :container_stop, :container_restart] do
    remote_detail(action, node, [name], container_job_data(node, name))
  end

  defp remote_detail(job_name, node, parameters, data)
       when is_atom(job_name) and is_binary(node) and is_list(parameters) and is_map(data) do
    Detail.new(job_name, Spec.new(Spec.Remote.new(node), parameters, data))
  end

  defp container_job_data(node, name) when is_binary(node) and is_binary(name),
    do: ContainerAction.new(node, name)
end
