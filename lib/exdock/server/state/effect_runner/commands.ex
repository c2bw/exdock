defmodule Exdock.Server.State.EffectRunner.Commands do
  @moduledoc false

  alias Exdock.Runtime.Coordinator
  alias Exdock.Server.State

  def run(%State{}, {:schedule_automation, %State.PeriodicJob{} = job}),
    do: Exdock.Server.AutomationScheduler.replace(job)

  def run(%State{}, {:server_command, command, opts}) when is_list(opts),
    do: Coordinator.command(nil, command, opts)
end
