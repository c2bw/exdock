defmodule Exdock.Server.Automation.Handler do
  @moduledoc """
  Interprets effects selected by the pure automation policy.
  """

  alias Exdock.Events
  alias Exdock.Runtime.Coordinator
  alias Exdock.Server.Automation.Policy

  @callback run([Policy.effect()]) :: :ok

  @spec run([Policy.effect()]) :: :ok
  def run(effects) when is_list(effects) do
    Enum.each(effects, &run_effect/1)
    :ok
  end

  defp run_effect({:command, operation_id, command, opts}),
    do: Coordinator.command(operation_id, command, opts)

  defp run_effect({:operation_finished, operation_id, kind, result}),
    do: Events.operation_finished(operation_id, kind, result)
end
