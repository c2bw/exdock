defmodule Exdock.Server.RegistryFetchLimiter.LeaseState.Bucket do
  @moduledoc "Owners and FIFO waiters isolated to one registry endpoint."

  alias Exdock.Server.RegistryFetchLimiter.LeaseState.{Owner, Waiter}

  defstruct owners: %{}, waiting: {[], []}

  @type t :: %__MODULE__{
          owners: %{optional(reference()) => Owner.t()},
          waiting: :queue.queue(Waiter.t())
        }

  @spec new() :: t()
  def new, do: %__MODULE__{waiting: :queue.new()}
end
