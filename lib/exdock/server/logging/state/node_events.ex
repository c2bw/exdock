defmodule Exdock.Server.Logging.State.NodeEvents do
  @moduledoc "Node connectivity transitions for activity state."

  alias Exdock.Server.Logging.{AppendEntry, Context, State, Status}
  alias Exdock.Server.Logging.State.Reducer
  alias Exdock.Server.Logging.Status.Utils

  @spec transition(State.t(), :up | :down, Exdock.NodeId.t(), Context.t()) ::
          {State.t(), [State.effect()]}
  def transition(%State{} = state, status, node, %Context{} = context)
      when status in [:up, :down] and is_binary(node) do
    {state, effects} = Reducer.append_log(state, AppendEntry.new(message(status), node), context)
    Reducer.update_status(state, &apply_status(&1, status), effects)
  end

  defp apply_status(%Status{} = status, :up),
    do: Utils.set_job_message(status, "Node Connected", "Fetching Data")

  defp apply_status(%Status{} = status, :down),
    do: Utils.set_job_message(status, "Node Disconnected", "OK")

  defp message(:up), do: :node_connected
  defp message(:down), do: :node_disconnected
end
