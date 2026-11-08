defmodule Exdock.Server.State.Change.Prepared do
  @moduledoc "State-change plan plus the context needed for derived reduction."

  alias Exdock.Server.State
  alias Exdock.Server.State.Change.Plan
  alias Exdock.Server.State.Domain

  @enforce_keys [:previous_state, :domain, :action, :plan]
  defstruct [:previous_state, :domain, :action, :plan]

  @type t :: %__MODULE__{
          previous_state: State.t(),
          domain: Domain.name(),
          action: atom(),
          plan: Plan.t()
        }
end
