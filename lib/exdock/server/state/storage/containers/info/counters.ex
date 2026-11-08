defmodule Exdock.Server.State.Storage.Containers.Info.Counters do
  @moduledoc """
  Status and priority buckets for a container collection.
  """

  @empty_status %{
    errored: %{count: 0, percentage: 0.0},
    unknown: %{count: 0, percentage: 0.0},
    outdated: %{count: 0, percentage: 0.0},
    updated: %{count: 0, percentage: 0.0}
  }

  @empty_priority %{
    ignore: 0,
    low: 0,
    normal: 0,
    high: 0,
    to_update: 0
  }

  defstruct status: @empty_status,
            priority: @empty_priority

  @type status_bucket :: %{count: integer(), percentage: float()}

  @type t :: %__MODULE__{
          status: %{
            errored: status_bucket(),
            unknown: status_bucket(),
            outdated: status_bucket(),
            updated: status_bucket()
          },
          priority: %{
            ignore: integer(),
            low: integer(),
            normal: integer(),
            high: integer(),
            to_update: integer()
          }
        }
end
