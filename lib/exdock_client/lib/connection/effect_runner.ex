defmodule Exdock.Client.Connection.EffectRunner do
  @moduledoc """
  Interprets connection cleanup and reconnect effects.

  The pure `Transition` module decides what should happen; this module performs
  transport and timer operations against the adapters stored in client state.
  """

  require Logger

  alias Exdock.Client.Connection.Session
  alias Exdock.Client.Connection.State
  alias Exdock.Client.Connection.Transition

  @spec execute_runtime(State.t(), term()) :: :ok
  def execute_runtime(%State{} = state, command) do
    state.runtime_executor.execute(command)
    :ok
  end

  @reconnect_interval 20_000
  @ssl_closed "SSL connection closed"

  @spec disconnect(State.t(), binary(), boolean()) :: State.t()
  def disconnect(%State{} = state, reason, reconnect? \\ true) do
    {state, effects} = Transition.disconnect(state, reason, reconnect?)
    Enum.reduce(effects, state, &execute/2)
  end

  @spec schedule_reconnect(State.t()) :: State.t()
  def schedule_reconnect(%State{} = state) do
    cond do
      not Session.reconnect_enabled?(state.session) ->
        cancel_reconnect(state)

      is_reference(state.reconnect_timer) ->
        state

      true ->
        reconnect_timer = state.timer.reconnect(@reconnect_interval)
        %{state | reconnect_timer: reconnect_timer}
    end
  end

  @spec cancel_reconnect(State.t()) :: State.t()
  def cancel_reconnect(%State{reconnect_timer: reconnect_timer} = state)
      when is_reference(reconnect_timer) do
    state.timer.cancel(reconnect_timer)
    %{state | reconnect_timer: nil}
  end

  def cancel_reconnect(%State{} = state), do: %{state | reconnect_timer: nil}

  defp execute({:log_disconnection, reason, reconnect?}, state) do
    reconnect_message =
      if reconnect?,
        do: "Scheduling reconnect...",
        else: "Will not attempt to reconnect."

    header =
      if reason == @ssl_closed,
        do: "Disconnected [#{@ssl_closed}].",
        else: "Disconnecting from server [#{reason}]."

    Logger.error("#{header} #{reconnect_message}")
    state
  end

  defp execute({:close_socket, socket}, state) do
    state.transport.close(socket)
    state
  end

  defp execute({:cancel_timer, timer}, state) do
    state.timer.cancel(timer)
    state
  end

  defp execute(:schedule_reconnect, state), do: schedule_reconnect(state)
end
