defmodule Exdock.Runtime.Mutation.Payload.ContainerLogs do
  @moduledoc "Typed container log-snapshot mutation payload."

  @enforce_keys [:node, :id, :logs, :occurred_at]
  defstruct [:node, :id, :logs, :occurred_at]

  @type t :: %__MODULE__{
          node: String.t(),
          id: String.t(),
          logs: [String.t()],
          occurred_at: DateTime.t()
        }
end
