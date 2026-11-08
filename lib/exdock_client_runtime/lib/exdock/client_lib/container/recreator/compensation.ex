defmodule Exdock.ClientLib.Container.Recreator.Compensation do
  @moduledoc """
  Builds and executes declarative rollback operations for container recreation.

  Compensation continues after an error so callers receive the best possible
  restoration attempt and a complete, ordered error report.
  """

  alias DockerEngineAPI.Model
  alias Exdock.ClientLib.Container.Recreator.{Operation, Plan}

  @type label :: term()
  @type step :: {label(), Operation.t()}

  @spec plan(map()) :: [step()]
  def plan(state) when is_map(state) do
    replacement_steps(state) ++
      network_steps(state) ++
      name_steps(state) ++
      running_steps(state)
  end

  @spec run([step()], (Operation.t() -> {:ok, term()} | {:error, term()})) ::
          [{label(), term()}]
  def run(steps, execute) when is_list(steps) and is_function(execute, 1) do
    steps
    |> Enum.reduce([], &run_step(&1, &2, execute))
    |> Enum.reverse()
  end

  defp replacement_steps(%{new_id: nil}), do: []

  defp replacement_steps(state) do
    [
      {:stop_replacement, {:stop, state.new_id}},
      {:delete_replacement, {:delete, state.new_id}}
    ]
  end

  defp network_steps(state) do
    state.detached_networks
    |> Enum.reverse()
    |> Enum.map(fn {network, endpoint} ->
      request = %Model.NetworkConnectRequest{
        Container: state.plan.original_id,
        EndpointConfig: endpoint
      }

      {{:reconnect_original_network, network}, {:connect, state.plan.original_id, network, request}}
    end)
  end

  defp name_steps(%{renamed: false}), do: []

  defp name_steps(state) do
    [
      {:restore_original_name, {:rename, state.plan.original_id, state.plan.original_name}}
    ]
  end

  defp running_steps(%{plan: %Plan{original_running: true}, stopped: true} = state) do
    [{:restart_original, {:start, state.plan.original_id}}]
  end

  defp running_steps(_state), do: []

  defp run_step({label, operation}, errors, execute) do
    case execute.(operation) do
      {:ok, _response} -> errors
      {:error, reason} -> [{label, reason} | errors]
    end
  rescue
    exception -> [{label, exception} | errors]
  end
end
