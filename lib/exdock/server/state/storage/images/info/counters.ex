defmodule Exdock.Server.State.Storage.Images.Info.Counters do
  @moduledoc """
  Lock/use buckets for an image collection.
  """

  defstruct status: %{
              locked: %{count: 0, percentage: 0.0},
              unused: %{count: 0, percentage: 0.0},
              in_use: %{count: 0, percentage: 0.0}
            }

  @type t :: %__MODULE__{
          status: %{
            locked: %{count: integer(), percentage: float()},
            unused: %{count: integer(), percentage: float()},
            in_use: %{count: integer(), percentage: float()}
          }
        }
end
