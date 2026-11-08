defmodule Exdock.Server.NodeLifecycle.Handler do
  @moduledoc """
  Interprets external effects selected by the node lifecycle policy.
  """

  alias Exdock.Events
  alias Exdock.Runtime.Coordinator
  alias Exdock.Server.State.EffectExecutor
  alias Phoenix.PubSub

  require Logger

  @spec run([term()]) :: :ok
  def run(effects) when is_list(effects) do
    Enum.each(effects, &run_effect/1)
    :ok
  end

  defp run_effect({:log, level, message}), do: Logger.log(level, message)

  defp run_effect({:state_effects, state, effects}),
    do: EffectExecutor.run(state, effects)

  defp run_effect({:pubsub, topic, message}),
    do: PubSub.broadcast(Exdock.PubSub, topic, message)

  defp run_effect({:event, topic, event}), do: Events.publish(topic, event)
  defp run_effect({:command, operation_id, command}), do: Coordinator.command(operation_id, command)
end
