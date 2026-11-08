defmodule Exdock.Server.Logging.State.Reducer do
  @moduledoc "Shared state/effect operations used by activity event reducers."

  alias Exdock.Server.Logging.{AppendEntry, Context, Log, State}

  @spec append_log(State.t(), AppendEntry.t(), Context.t()) :: {State.t(), [State.effect()]}
  def append_log(%State{} = state, %AppendEntry{} = input, %Context{} = context) do
    logs = Log.add_entry(state.logs, input, context.id, context.now)
    state = state |> Map.put(:logs, logs) |> bump_revision()
    effects = if input.broadcast?, do: [broadcast_effect(:log, logs, state)], else: []
    {state, effects}
  end

  @spec update_logs(State.t(), function()) :: {State.t(), [State.effect()]}
  def update_logs(%State{} = state, update_fn) when is_function(update_fn, 1) do
    logs = update_fn.(state.logs)
    state = state |> Map.put(:logs, logs) |> bump_revision()
    {state, [broadcast_effect(:log, logs, state)]}
  end

  @spec update_status(State.t(), function(), [State.effect()]) :: {State.t(), [State.effect()]}
  def update_status(%State{} = state, update_fn, prior_effects \\ [])
      when is_function(update_fn, 1) and is_list(prior_effects) do
    status = update_fn.(state.job_status)
    state = state |> Map.put(:job_status, status) |> bump_revision()
    {state, prior_effects ++ [broadcast_effect(:status, status, state)]}
  end

  @spec apply_status_transition(State.t(), term(), term(), [State.effect()], Context.t()) ::
          {State.t(), [State.effect()]}
  def apply_status_transition(state, status, nil, lifecycle_effects, %Context{}) do
    update_status(state, fn _current -> status end, lifecycle_effects)
  end

  def apply_status_transition(
        %State{} = state,
        status,
        {job_id, job_result, opts},
        lifecycle_effects,
        %Context{} = context
      ) do
    logs = Log.update_entry(state.logs, job_id, job_result, context.now, opts)

    state =
      state
      |> Map.put(:job_status, status)
      |> Map.put(:logs, logs)
      |> bump_revision()

    effects =
      lifecycle_effects ++
        [
          broadcast_effect(:status, status, state),
          broadcast_effect(:log, logs, state)
        ]

    {state, effects}
  end

  defp broadcast_effect(domain, data, state),
    do: {:broadcast, domain, data, state.revision}

  defp bump_revision(%State{revision: revision} = state),
    do: %{state | revision: revision + 1}
end
