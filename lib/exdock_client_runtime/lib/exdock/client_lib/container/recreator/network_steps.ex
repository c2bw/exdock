defmodule Exdock.ClientLib.Container.Recreator.NetworkSteps do
  @moduledoc """
  Builds declarative network operations for container recreation.

  Each step carries its failure label and the state transition to apply after
  a successful Docker operation. The workflow can execute every network phase
  through one fail-fast interpreter while retaining exactly the detachments
  that rollback must compensate.
  """

  alias DockerEngineAPI.Model
  alias Exdock.ClientLib.Container.Recreator.{Operation, Plan}

  @type success :: :unchanged | {:record_detachment, String.t(), term()}
  @type step :: {term(), Operation.t(), success()}

  @spec disconnect_original(Plan.t()) :: [step()]
  def disconnect_original(%Plan{} = plan) do
    Enum.map(plan.original_networks, fn {network, endpoint} ->
      request = %Model.NetworkDisconnectRequest{Container: plan.original_id, Force: true}

      {
        {:disconnect_original_network, network},
        {:disconnect, plan.original_id, network, request},
        {:record_detachment, network, endpoint}
      }
    end)
  end

  @spec disconnect_replacement(String.t(), map()) :: [step()]
  def disconnect_replacement(replacement_id, networks)
      when is_binary(replacement_id) and is_map(networks) do
    Enum.map(networks, fn {network, _endpoint} ->
      request = %Model.NetworkDisconnectRequest{Container: replacement_id, Force: true}

      {
        {:disconnect_replacement_network, network},
        {:disconnect, replacement_id, network, request},
        :unchanged
      }
    end)
  end

  @spec connect_replacement(Plan.t(), String.t()) :: [step()]
  def connect_replacement(%Plan{} = plan, replacement_id) when is_binary(replacement_id) do
    Enum.map(plan.original_networks, fn {network, endpoint} ->
      request = %Model.NetworkConnectRequest{
        Container: replacement_id,
        EndpointConfig: endpoint
      }

      {
        {:connect_replacement_network, network},
        {:connect, replacement_id, network, request},
        :unchanged
      }
    end)
  end

  @spec apply_success(map(), success()) :: map()
  def apply_success(state, :unchanged), do: state

  def apply_success(state, {:record_detachment, network, endpoint}) do
    Map.update!(state, :detached_networks, &[{network, endpoint} | &1])
  end
end
