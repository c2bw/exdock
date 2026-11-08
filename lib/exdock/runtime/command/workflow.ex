defmodule Exdock.Runtime.Command.Workflow do
  @moduledoc "Typed continuation command for multi-step automation workflows."

  @enforce_keys [:step, :remaining]
  defstruct [:step, :remaining]

  @type step :: :registry_fetch | :node_refresh | :containers_update
  @type t :: %__MODULE__{step: step(), remaining: [step()]}

  @spec new(step(), [step()]) :: t()
  def new(step, remaining) when is_atom(step) and is_list(remaining),
    do: %__MODULE__{step: step, remaining: remaining}
end
