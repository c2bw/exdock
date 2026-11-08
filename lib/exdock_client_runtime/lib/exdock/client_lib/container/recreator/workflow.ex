defmodule Exdock.ClientLib.Container.Recreator.Workflow do
  @moduledoc """
  Executes the Docker recreation workflow and tracks compensation state.

  Progress delivery is injected by the facade, keeping this module focused on
  Docker operations, state transitions, and rollback ordering.
  """

  alias Exdock.ClientLib.Container.Recreator.{Compensation, NetworkSteps, Operation, Plan, Readiness}
  alias Exdock.Docker.Error

  defstruct [
    :conn,
    :ops,
    :plan,
    :new_id,
    :progress,
    options: [],
    stopped: false,
    renamed: false,
    detached_networks: []
  ]

  @type cleanup_result ::
          {:ok, String.t()}
          | {:cleanup_failed, String.t(), String.t(), term()}
  @type result ::
          {:ok, String.t(), cleanup_result()}
          | {:error, term(), term(), [{term(), term()}]}

  @spec run(term(), String.t(), module(), (String.t() -> term()), keyword()) :: result()
  def run(conn, container_identifier, ops, progress, options \\ [])
      when is_binary(container_identifier) and is_atom(ops) and is_function(progress, 1) do
    case prepare(conn, container_identifier, ops, progress, options) do
      {:ok, state} ->
        case replace(state) do
          {:ok, state} -> commit(state)
          {:error, state, operation, reason} -> rollback_error(state, operation, reason)
        end

      {:error, operation, reason} ->
        {:error, operation, reason, []}
    end
  end

  defp prepare(conn, identifier, ops, progress, options) do
    progress.("inspecting")

    with {:ok, inspect} <- wrap(Operation.execute(ops, conn, {:inspect, identifier}), :inspect_original),
         {:ok, plan} <- build_plan(inspect),
         :ok <- require_image(ops, conn, plan) do
      {:ok,
       %__MODULE__{
         conn: conn,
         ops: ops,
         plan: plan,
         progress: progress,
         options: options
       }}
    end
  end

  defp build_plan(inspect) do
    case Plan.build(inspect) do
      {:ok, plan} -> {:ok, plan}
      {:error, reason} -> {:error, :inspect_original, reason}
    end
  end

  defp require_image(ops, conn, plan) do
    # Let Docker resolve tags, digests, IDs and registry aliases consistently.
    case Operation.execute(ops, conn, {:inspect_image, plan.create_request."Image"}) do
      {:ok, %{Id: id}} when is_binary(id) ->
        :ok

      {:ok, _} ->
        {:error, :inspect_image, :malformed_response}

      {:error, reason} ->
        if Error.new(:inspect_image, reason).status == 404,
          do: {:error, :image_unavailable, plan.image_tag},
          else: {:error, :inspect_image, reason}
    end
  end

  defp replace(state) do
    with {:ok, state} <- stop_original(state),
         {:ok, state} <- rename_original(state),
         {:ok, state} <- disconnect_original_networks(state),
         {:ok, state} <- create_replacement(state),
         {:ok, state} <- disconnect_default_networks(state),
         {:ok, state} <- connect_replacement_networks(state),
         {:ok, state} <- start_replacement(state),
         {:ok, state} <- verify_replacement(state) do
      {:ok, state}
    end
  end

  defp stop_original(state) do
    progress(state, "stopping")

    case execute(state, {:stop, state.plan.original_id}) do
      {:ok, _response} -> {:ok, %{state | stopped: true}}
      {:error, reason} -> failure(state, :stop_original, reason)
    end
  end

  defp rename_original(state) do
    progress(state, "renaming")

    case execute(state, {:rename, state.plan.original_id, state.plan.temporary_name}) do
      {:ok, _response} -> {:ok, %{state | renamed: true}}
      {:error, reason} -> failure(state, :rename_original, reason)
    end
  end

  defp disconnect_original_networks(state) do
    progress(state, "disconnecting networks")

    state.plan
    |> NetworkSteps.disconnect_original()
    |> run_network_steps(state)
  end

  defp create_replacement(state) do
    progress(state, "creating")

    case execute(state, {:create, state.plan.original_name, state.plan.create_request}) do
      {:ok, %{Id: id}} when is_binary(id) -> {:ok, %{state | new_id: id}}
      {:ok, _response} -> failure(state, :create_replacement, :malformed_response)
      {:error, reason} -> failure(state, :create_replacement, reason)
    end
  end

  defp disconnect_default_networks(state) do
    with {:ok, %{NetworkSettings: %{Networks: networks}}} <-
           wrap(execute(state, {:inspect, state.new_id}), :inspect_replacement) do
      state.new_id
      |> NetworkSteps.disconnect_replacement(networks)
      |> run_network_steps(state)
    else
      {:error, operation, reason} -> failure(state, operation, reason)
      _other -> failure(state, :inspect_replacement, :malformed_response)
    end
  end

  defp connect_replacement_networks(state) do
    state.plan
    |> NetworkSteps.connect_replacement(state.new_id)
    |> run_network_steps(state)
  end

  defp run_network_steps(steps, state) do
    Enum.reduce_while(steps, {:ok, state}, fn {label, operation, success}, {:ok, state} ->
      case execute(state, operation) do
        {:ok, _response} ->
          {:cont, {:ok, NetworkSteps.apply_success(state, success)}}

        {:error, reason} ->
          {:halt, failure(state, label, reason)}
      end
    end)
  end

  defp start_replacement(%{plan: %Plan{original_running: false}} = state), do: {:ok, state}

  defp start_replacement(state) do
    progress(state, "starting")

    case execute(state, {:start, state.new_id}) do
      {:ok, _response} -> {:ok, state}
      {:error, reason} -> failure(state, :start_replacement, reason)
    end
  end

  defp commit(state) do
    progress(state, "deleting old")

    cleanup_result =
      case execute(state, {:delete, state.plan.original_id}) do
        {:ok, _response} ->
          {:ok, state.plan.original_name}

        {:error, reason} ->
          {:cleanup_failed, state.plan.original_name, state.plan.temporary_name, reason}
      end

    {:ok, state.new_id, cleanup_result}
  end

  defp verify_replacement(%{plan: %Plan{original_running: false}} = state), do: {:ok, state}

  defp verify_replacement(state) do
    progress(state, "checking readiness")

    case Readiness.await(fn -> execute(state, {:inspect, state.new_id}) end, state.options) do
      :ok -> {:ok, state}
      {:error, reason} -> failure(state, :verify_replacement, reason)
    end
  end

  defp rollback_error(state, operation, reason) do
    rollback_errors =
      state
      |> Compensation.plan()
      |> Compensation.run(&execute(state, &1))

    {:error, operation, reason, rollback_errors}
  end

  defp failure(state, operation, reason), do: {:error, state, operation, reason}
  defp wrap({:ok, value}, _operation), do: {:ok, value}
  defp wrap({:error, reason}, operation), do: {:error, operation, reason}
  defp progress(%__MODULE__{progress: progress}, message), do: progress.(message)
  defp execute(%__MODULE__{ops: ops, conn: conn}, operation), do: Operation.execute(ops, conn, operation)
end
