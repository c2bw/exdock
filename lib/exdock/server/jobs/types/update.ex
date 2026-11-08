defmodule Exdock.Server.Jobs.Update do
  @moduledoc """
  In-flight progress update for a running job.

  Remote multi-node jobs can mark one node as finished by setting
  `remove_node`; otherwise updates are informational and leave the running
  target set intact.
  """

  alias Exdock.Server.Jobs.Payload

  @type id :: String.t()
  @type node_id :: Exdock.NodeId.t() | nil
  @type payload :: Payload.update()
  @type error :: Payload.error()

  defstruct [
    :id,
    :node,
    :update,
    :remove_node,
    error: nil
  ]

  @type t :: %__MODULE__{
          id: id(),
          node: node_id(),
          update: payload(),
          remove_node: boolean(),
          error: error()
        }

  @spec new(id(), node_id(), payload(), boolean(), error()) :: t()
  def new(id, node, update, remove, error \\ nil)
      when is_binary(id) and (is_binary(node) or is_nil(node)) and is_boolean(remove) do
    %__MODULE__{
      id: id,
      node: node,
      update: update,
      remove_node: remove,
      error: error
    }
  end
end
