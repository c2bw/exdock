defmodule Exdock.Server.State.Change.Behaviour do
  @moduledoc """
  Contract implemented by server state domain reducers.

  `plan/2` prepares direct mutations for a domain. Cross-domain dependencies live
  in `Exdock.Server.State.Domain`.
  """

  alias Exdock.Server.State

  @doc """
  Called when the module has to change its state.

  The callback returns the modified state, broadcast options for the module
  that handled the direct change, and effects to execute after the full state
  transition has been assembled.
  """
  @callback plan(State.t(), Exdock.Runtime.Mutation.t()) ::
              Exdock.Server.State.Change.Plan.t()

  @doc "Execute one normalized mutation whose persistence was deferred by `plan/2`."
  @callback execute_persisted(State.t(), Exdock.Runtime.Mutation.t()) ::
              Exdock.Server.State.Change.Plan.outcome()

  @doc """
  Recompute derived data using the latest full server state.
  """
  @callback reload(State.t()) :: State.t()

  @doc """
  Return data to broadcast plus broadcast options.
  """
  @callback broadcast(State.t()) :: {any(), keyword()}
end
