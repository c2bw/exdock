defmodule Exdock.Server.State.EffectRunner do
  @moduledoc "Production dispatcher for focused state-effect interpreters."

  alias Exdock.Server.State
  alias Exdock.Server.State.EffectRunner.{Broadcast, Commands, Jobs, Logging, Notifications}

  @spec run(State.t(), [Exdock.Server.State.Effects.effect()]) :: :ok
  def run(%State{} = state, effects) when is_list(effects) do
    Enum.each(effects, &dispatch(state, &1))
    :ok
  end

  defp dispatch(state, {:broadcast, _domain, _opts} = effect),
    do: Broadcast.run(state, effect)

  defp dispatch(state, {:broadcast_projection, _projection} = effect),
    do: Broadcast.run(state, effect)

  defp dispatch(state, {:schedule_automation, _job} = effect),
    do: Commands.run(state, effect)

  defp dispatch(state, {:server_command, _command, _opts} = effect),
    do: Commands.run(state, effect)

  defp dispatch(state, {kind, _payload} = effect)
       when kind in [:job_info, :job_update, :job_result],
       do: Jobs.run(state, effect)

  defp dispatch(state, {:container_status, _transition} = effect),
    do: Notifications.run(state, effect)

  defp dispatch(state, {:notify_image_tag, _tag_info} = effect),
    do: Notifications.run(state, effect)

  defp dispatch(state, {:log, _level, _message} = effect),
    do: Logging.run(state, effect)

  defp dispatch(state, {:log_entry, _entry} = effect),
    do: Logging.run(state, effect)
end
