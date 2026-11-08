defmodule Exdock.Server.Jobs.Info do
  @moduledoc """
  Public metadata broadcast with job lifecycle events.

  `Info` deliberately exposes only stable, user-facing job attributes instead
  of the full runnable job struct, so status/log subscribers do not depend on
  queue internals.
  """

  alias Exdock.Server.Jobs

  defstruct [
    :name,
    :automated
  ]

  @type t :: %__MODULE__{
          name: atom(),
          automated: boolean()
        }

  @spec new(Jobs.Job.t()) :: t()
  def new(%Jobs.Job{name: name, is_automated: is_automated}), do: new(name, is_automated)

  defp new(name, automated) when is_atom(name) and is_boolean(automated) do
    %__MODULE__{
      name: name,
      automated: automated
    }
  end
end
