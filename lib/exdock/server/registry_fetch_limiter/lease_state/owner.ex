defmodule Exdock.Server.RegistryFetchLimiter.LeaseState.Owner do
  @moduledoc "A monitored process holding one registry-fetch lease."

  @enforce_keys [:pid, :lease, :monitor]
  defstruct [:pid, :lease, :monitor]

  @type t :: %__MODULE__{pid: pid(), lease: reference(), monitor: reference()}
end
