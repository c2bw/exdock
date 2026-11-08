defmodule Exdock.Server.Broadcast.Policy do
  @moduledoc """
  Pure transition policy for batched broadcasts.

  Transitions return updated state plus effects for the GenServer shell to
  interpret. Effects never perform timers or publication themselves.
  """

  alias Exdock.Server.Broadcast.BroadcastState

  @broadcast_window_ms 100
  @default_delay_ms 1000

  @type effect ::
          {:schedule, term(), non_neg_integer()}
          | {:publish, BroadcastState.payload_by_type()}
  @type transition :: {BroadcastState.t(), [effect()]}

  @spec stage(BroadcastState.t(), atom(), any(), keyword()) :: transition()
  def stage(state, type, payload, opts) when is_atom(type) and is_list(opts) do
    if Keyword.get(opts, :delayed, false) do
      stage_delayed(state, type, payload, opts)
    else
      state
      |> BroadcastState.put_immediate_payload(type, payload)
      |> flush_if_ready(opts)
    end
  end

  @spec cooldown(BroadcastState.t()) :: transition()
  def cooldown(state) do
    {state, publish_effects} = flush_immediate_payloads(state)
    {state, [{:schedule, {:ready_to_broadcast}, @broadcast_window_ms} | publish_effects]}
  end

  @spec ready(BroadcastState.t()) :: transition()
  def ready(state) do
    # Updates can arrive after cooldown's flush while the window remains closed.
    # Flush them now so the final status never waits for unrelated activity.
    state
    |> BroadcastState.open_broadcast_window()
    |> flush_if_ready([])
  end

  @spec delayed_ready(BroadcastState.t(), atom(), pos_integer()) :: transition()
  def delayed_ready(state, type, generation) when is_atom(type) and is_integer(generation) do
    case BroadcastState.fetch_delayed_payload(state, type, generation) do
      {:ok, payload} ->
        state
        |> BroadcastState.delete_delayed_payload(type)
        |> BroadcastState.put_immediate_payload(type, payload)
        |> close_window_and_flush()

      :error ->
        {state, []}
    end
  end

  defp stage_delayed(state, type, payload, opts) do
    if BroadcastState.delayed_payload_active?(state, type) do
      {BroadcastState.put_delayed_payload(state, type, payload), []}
    else
      delay_ms = Keyword.get(opts, :delay_ms, @default_delay_ms)
      {state, generation} = BroadcastState.start_delayed_payload(state, type, payload)
      {state, [{:schedule, {:broadcast_delayed, type, generation}, delay_ms}]}
    end
  end

  defp flush_if_ready(state, opts) do
    if Keyword.get(opts, :force, false) or
         (state.broadcast_window_open and state.immediate_flush_needed) do
      close_window_and_flush(state)
    else
      {state, []}
    end
  end

  defp close_window_and_flush(state) do
    state
    |> BroadcastState.close_broadcast_window()
    |> flush_immediate_payloads()
    |> prepend_effect({:schedule, {:cooldown}, @broadcast_window_ms})
  end

  defp flush_immediate_payloads(state) do
    payloads = BroadcastState.immediate_payloads(state)
    {BroadcastState.flush_immediate_buckets(state), publish_effects(payloads)}
  end

  defp publish_effects(payloads) when map_size(payloads) == 0, do: []
  defp publish_effects(payloads), do: [{:publish, payloads}]

  defp prepend_effect({state, effects}, effect), do: {state, [effect | effects]}
end
