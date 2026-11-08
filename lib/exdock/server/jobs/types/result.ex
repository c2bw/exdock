defmodule Exdock.Server.Jobs.Result do
  @moduledoc """
  Terminal result for a local or remote job.

  The dispatcher treats a result as the signal to broadcast completion, update
  package state, run dependent queued jobs, and clean up node/running indexes.
  """

  alias Exdock.Server.Jobs.Payload

  defstruct [
    :id,
    :node,
    :data,
    :error
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          node: String.t() | nil,
          data: Payload.result(),
          error: Payload.error()
        }

  @spec new(String.t(), String.t() | nil, Payload.result(), Payload.error()) :: t()
  def new(id, node, data, error \\ nil)
      when is_binary(id) and (is_binary(node) or is_nil(node)) do
    %__MODULE__{
      id: id,
      node: node,
      data: data,
      error: error
    }
  end
end
