defmodule Exdock.Server.State.ChangeProbe do
  @moduledoc false

  alias Exdock.Runtime.Mutation
  alias Exdock.Server.State
  alias Exdock.Server.State.Change.Outcome

  def execute_persisted(%State{} = state, %Mutation{action: :probe, data: owner}) when is_pid(owner) do
    send(owner, :persisted)
    Outcome.planned(state, [], [])
  end
end
