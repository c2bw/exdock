defmodule Exdock.Client.Connection.Transition do
  @moduledoc """
  Pure state transitions for transport resource cleanup and reconnect policy.

  The TCP GenServer executes the returned effects; this module decides which
  resources must be closed or cancelled and what the resulting session is.
  """

  alias Exdock.Client.Connection.Session
  alias Exdock.Client.Connection.State

  @type effect ::
          {:log_disconnection, binary(), boolean()}
          | {:close_socket, term()}
          | {:cancel_timer, reference()}
          | :schedule_reconnect

  @spec disconnect(State.t(), binary(), boolean()) :: {State.t(), [effect()]}
  def disconnect(%State{} = state, reason, reconnect? \\ true)
      when is_binary(reason) and is_boolean(reconnect?) do
    reconnect? = reconnect? and Session.reconnect_enabled?(state.session)
    {:ok, session} = Session.transition(state.session, :disconnect)
    session = if reconnect?, do: session, else: Session.disable_reconnect(session)

    effects =
      [{:log_disconnection, reason, reconnect?}]
      |> maybe_add_effect(state.socket, &{:close_socket, &1})
      |> maybe_add_effect(state.heartbeat_timer, &{:cancel_timer, &1})
      |> reconnect_effects(state.reconnect_timer, reconnect?)

    state = %{
      state
      | session: session,
        socket: nil,
        wire: nil,
        heartbeat_timer: nil,
        reconnect_timer: retained_reconnect_timer(state.reconnect_timer, reconnect?)
    }

    {state, effects}
  end

  defp maybe_add_effect(effects, nil, _build), do: effects
  defp maybe_add_effect(effects, value, build), do: effects ++ [build.(value)]

  defp reconnect_effects(effects, reconnect_timer, false) when is_reference(reconnect_timer),
    do: effects ++ [{:cancel_timer, reconnect_timer}]

  defp reconnect_effects(effects, _reconnect_timer, false), do: effects
  defp reconnect_effects(effects, nil, true), do: effects ++ [:schedule_reconnect]
  defp reconnect_effects(effects, _reconnect_timer, true), do: effects

  defp retained_reconnect_timer(reconnect_timer, true), do: reconnect_timer
  defp retained_reconnect_timer(_reconnect_timer, false), do: nil
end
