defmodule Exdock.Server.Logging.Status.ContainerDifferences do
  @moduledoc """
  Computes the observable container changes between two node snapshots.

  This module is intentionally independent of jobs, logs, storage, and
  processes. Callers provide the compact before/response tuple formats and
  receive only changed entries, grouped under the keys from the before
  snapshot.
  """

  @type node_key :: String.t()
  @type container_name :: String.t()
  @type before_container :: {container_name(), {:before, boolean()}}
  @type response_container :: {container_name(), {atom(), boolean()}}

  @type container_change ::
          {container_name(), {:error, atom()} | {:new, boolean()} | {:ok, boolean() | :vanished}}

  @type changes_by_node :: %{node_key() => [container_change()]}

  @spec calculate(
          %{node_key() => [before_container()]},
          %{node_key() => [response_container()]}
        ) :: changes_by_node()
  def calculate(before_snapshot, response_snapshot)
      when is_map(before_snapshot) and is_map(response_snapshot) do
    responses_by_node = index_responses_by_node(response_snapshot)

    before_snapshot
    |> Enum.reduce(%{}, fn {node, before_containers}, differences ->
      changes = changes_for_node(before_containers, responses_for_node(responses_by_node, node))

      if changes == [] do
        differences
      else
        Map.put(differences, node, changes)
      end
    end)
  end

  defp changes_for_node(before_containers, response_containers) do
    before_by_name = Map.new(before_containers, &before_entry/1)
    response_names = MapSet.new(response_containers, &elem(&1, 0))

    response_containers
    |> Enum.flat_map(&change_from_response(&1, before_by_name))
    |> Enum.concat(vanished_containers(before_containers, response_names))
    |> Enum.sort()
  end

  defp before_entry({name, {:before, running?}}), do: {name, running?}

  defp change_from_response({name, {fetch_result, running?}}, before_by_name) do
    case {fetch_result, Map.fetch(before_by_name, name)} do
      {:ok, {:ok, ^running?}} -> []
      {:ok, {:ok, _previous_running?}} -> [{name, {:ok, running?}}]
      {:ok, :error} -> [{name, {:new, running?}}]
      {error, _before_state} -> [{name, {:error, error}}]
    end
  end

  defp vanished_containers(before_containers, response_names) do
    before_containers
    |> Enum.reject(fn {name, _status} -> MapSet.member?(response_names, name) end)
    |> Enum.map(fn {name, _status} -> {name, {:ok, :vanished}} end)
  end

  defp responses_for_node(responses_by_node, node) do
    Map.get(responses_by_node, node, [])
  end

  defp index_responses_by_node(response_snapshot) do
    Enum.reduce(response_snapshot, %{}, fn {node, containers}, responses_by_node ->
      Map.update(responses_by_node, node, containers, &(&1 ++ containers))
    end)
  end
end
