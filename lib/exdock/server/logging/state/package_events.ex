defmodule Exdock.Server.Logging.State.PackageEvents do
  @moduledoc "Package lifecycle transitions for activity state."

  alias Exdock.Server.Jobs.{Event, Package}
  alias Exdock.Server.Logging.{AppendEntry, Context, Log, State}
  alias Exdock.Server.Logging.State.Reducer

  @spec transition(State.t(), Event.t(), Context.t()) :: {State.t(), [State.effect()]}
  def transition(
        %State{} = state,
        %Event{type: :package_started, package: %Package{log_on_start: nil}},
        %Context{}
      ),
      do: {state, []}

  def transition(
        %State{} = state,
        %Event{
          type: :package_started,
          package: %Package{id: id, name: name, details: details, log_on_start: log_data}
        },
        %Context{} = context
      ) do
    automated? = Enum.any?(details, & &1.is_automated)

    Reducer.append_log(
      state,
      AppendEntry.new(name, {:mass, log_data}, id, automated: automated?),
      context
    )
  end

  def transition(
        %State{} = state,
        %Event{type: :package_finished, package_id: id, error: completion_error},
        %Context{} = context
      )
      when is_binary(id) do
    status = if is_nil(completion_error), do: :finished, else: :errored
    Reducer.update_logs(state, &Log.update_entry(&1, id, status, context.now))
  end
end
