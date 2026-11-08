defmodule Exdock.Server.Logging.Status.NodeRefresh.Progress do
  @moduledoc """
  Pure response accumulator for a multi-node refresh.

  The status job owns dashboard and log projection. This module owns pending
  nodes, response counters, normalized container snapshots, progress messages,
  and the terminal success/error decision.
  """

  alias Exdock.Protocol.Snapshot
  alias Exdock.Server.Jobs.NodeRefreshSnapshot

  @type t :: %{
          errored_response: non_neg_integer(),
          waiting_response: integer(),
          wanted_nodes: [term()],
          containers_before: map(),
          containers_response: map()
        }

  @type outcome :: %{
          waiting: integer(),
          errored: non_neg_integer(),
          remaining_nodes: [term()],
          message: String.t()
        }

  @spec new(map(), [term()]) :: t()
  def new(containers_before \\ %{}, locations \\ [])
      when is_map(containers_before) and is_list(locations) do
    %{
      errored_response: 0,
      waiting_response: length(locations),
      wanted_nodes: locations,
      containers_before: containers_before,
      containers_response: %{}
    }
  end

  @spec restore(term(), [term()]) :: t()
  def restore(data, locations) when is_map(data) and is_list(locations) do
    Map.merge(new(%{}, locations), data)
  end

  def restore(_data, locations) when is_list(locations), do: new(%{}, locations)

  @spec track(t(), [term()]) :: t()
  def track(progress, locations) when is_map(progress) and is_list(locations) do
    %{progress | wanted_nodes: locations, waiting_response: length(locations)}
  end

  @spec record_response(t(), term(), map(), term()) :: {t(), outcome()}
  def record_response(progress, node, containers, error)
      when is_map(progress) and is_map(containers) do
    remaining_nodes = Enum.reject(progress.wanted_nodes, &(&1 == node))
    waiting = progress.waiting_response - 1
    errored = progress.errored_response + error_increment(error)

    progress = %{
      progress
      | wanted_nodes: remaining_nodes,
        waiting_response: waiting,
        errored_response: errored,
        containers_response: Map.put(progress.containers_response, node, normalize_response(containers))
    }

    {progress,
     %{
       waiting: waiting,
       errored: errored,
       remaining_nodes: remaining_nodes,
       message: progress_message(waiting, errored)
     }}
  end

  @spec completion(t()) :: :pending | {:complete, nil | :error}
  def completion(%{wanted_nodes: [], errored_response: 0}), do: {:complete, nil}

  def completion(%{wanted_nodes: []}), do: {:complete, :error}
  def completion(_progress), do: :pending

  @spec normalize_response(
          NodeRefreshSnapshot.t()
          | %{
              ok: [Snapshot.Container.t()],
              errored: [{String.t(), Snapshot.Container.t()}]
            }
        ) :: [{String.t(), {term(), boolean()}}]
  def normalize_response(%NodeRefreshSnapshot{container_results: containers}),
    do: normalize_response(containers)

  def normalize_response(containers) when is_map(containers) do
    ok_entries =
      containers
      |> Map.get(:ok, [])
      |> Enum.map(fn container -> {container.name, {:ok, container.is_running}} end)

    error_entries =
      containers
      |> Map.get(:errored, [])
      |> Enum.map(fn {error, container} ->
        {container.name, {error, container.is_running}}
      end)

    ok_entries ++ error_entries
  end

  defp error_increment(nil), do: 0
  defp error_increment(_error), do: 1

  defp progress_message(waiting, 0), do: "waiting for [#{waiting}] nodes"

  defp progress_message(waiting, errored),
    do: "nodes: [#{waiting}] waiting, [#{errored}] errored"
end
