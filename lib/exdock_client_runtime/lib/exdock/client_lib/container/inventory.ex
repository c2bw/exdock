defmodule Exdock.ClientLib.Container.Inventory do
  @moduledoc """
  Collects Docker container inventory and maps it to protocol snapshots.
  """

  require Logger

  alias DockerEngineAPI.Model
  alias Exdock.ClientLib.Container.{Resources, SnapshotMapper}
  alias Exdock.ClientLib.Utils
  alias Exdock.Docker
  alias Exdock.Docker.Error
  alias Exdock.Protocol.Snapshot.Container, as: ContainerSnapshot

  @type snapshot :: ContainerSnapshot.t()

  @spec image_info(Exdock.Docker.Engine.connection(), String.t()) ::
          {:ok, %{image_tag: String.t(), image_id: String.t()}} | {:error, Error.t()}
  def image_info(conn, id) when is_binary(id) do
    case Docker.Local.Container.inspect(conn, id) do
      {:ok, %Model.ContainerInspectResponse{:Image => image_id, :Config => %{:Image => tag}}} ->
        {:ok, %{image_tag: tag, image_id: image_id}}

      {:error, error} ->
        {:error, Utils.docker_error(:container_inspect, error)}
    end
  end

  @spec get_all(Exdock.Docker.Engine.connection(), boolean(), keyword()) ::
          {:ok, %{ok: [snapshot()], errored: [{Error.t(), snapshot()}]}}
          | {:error, Error.t()}
  def get_all(conn, retrieve_resources, opts \\ [status: :all]) do
    case Docker.Local.Container.list(conn) do
      {:ok, summaries} ->
        summaries
        |> filter_status(Keyword.get(opts, :status))
        |> parallel_fetch(conn, retrieve_resources)

      {:error, error} ->
        {:error, Utils.docker_error(:container_list, error)}
    end
  end

  defp filter_status(summaries, :running),
    do: Enum.filter(summaries, fn %{:State => state} -> state == "running" end)

  defp filter_status(summaries, :stopped),
    do: Enum.reject(summaries, fn %{:State => state} -> state == "running" end)

  defp filter_status(summaries, _status), do: summaries

  defp parallel_fetch(summaries, conn, retrieve_resources) do
    containers =
      summaries
      |> Utils.async_stream(&fetch_container(conn, &1, retrieve_resources))
      |> Enum.reduce(%{ok: [], errored: []}, &collect_result/2)

    {:ok, containers}
  end

  defp collect_result({:ok, {:ok, container}}, acc),
    do: %{acc | ok: [container | acc.ok]}

  defp collect_result({:ok, {:error, error, container}}, acc),
    do: %{acc | errored: [{error, container} | acc.errored]}

  defp fetch_container(conn, %{:Id => id} = summary, retrieve_resources) do
    case Docker.Local.Container.inspect(conn, id) do
      {:ok, inspect} ->
        snapshot = SnapshotMapper.from_inspect(summary, inspect)
        log_snapshot(snapshot)
        Resources.maybe_schedule(conn, snapshot, retrieve_resources)
        {:ok, snapshot}

      {:error, error} ->
        {:error, Utils.docker_error(:container_inspect, error), SnapshotMapper.from_summary(summary)}
    end
  end

  defp log_snapshot(%ContainerSnapshot{} = snapshot) do
    stack = if snapshot.stack_name == "", do: "", else: " Stack Name: #{snapshot.stack_name}"

    Logger.debug("Container: #{snapshot.name}#{stack} Image Tag: #{snapshot.image_tag} Image ID: #{snapshot.image_id}")
  end
end
