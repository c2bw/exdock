defmodule Exdock.Server.State.Storage.Containers.Info.Data do
  @moduledoc """
  Count and flag summary for one filtered container collection.
  """

  alias Exdock.Server.State.Storage.Containers.Info.Counters

  defstruct stacks_count: 0,
            containers_count: 0,
            latest_started_at: nil,
            restarting?: false,
            counters: %Counters{}

  @type t :: %__MODULE__{
          stacks_count: integer(),
          containers_count: integer(),
          latest_started_at: DateTime.t() | nil,
          restarting?: boolean(),
          counters: Counters.t()
        }
end
