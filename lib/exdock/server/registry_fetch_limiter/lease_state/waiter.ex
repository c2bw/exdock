defmodule Exdock.Server.RegistryFetchLimiter.LeaseState.Waiter do
  @moduledoc "A monitored FIFO waiter for a registry-fetch lease."

  @enforce_keys [:from, :pid, :monitor]
  defstruct [:from, :pid, :monitor]

  @type t :: %__MODULE__{
          from: GenServer.from(),
          pid: pid(),
          monitor: reference()
        }

  @spec new(GenServer.from(), reference()) :: t()
  def new({pid, _tag} = from, monitor) when is_pid(pid) and is_reference(monitor) do
    %__MODULE__{from: from, pid: pid, monitor: monitor}
  end
end
