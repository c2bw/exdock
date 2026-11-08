defmodule Exdock.Server.Jobs.Message do
  @moduledoc """
  Informational message emitted by a running job.

  Messages are not terminal results; they carry progress text or structured
  details for logs/status components while the job remains active.
  """

  alias Exdock.Server.Jobs.Payload

  defstruct [
    :id,
    :name,
    :node,
    :message
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          name: atom(),
          node: String.t() | nil,
          message: Payload.message()
        }

  @spec new(String.t(), atom(), String.t() | nil, Payload.message()) :: t()
  def new(id, name, node, message)
      when is_binary(id) and is_atom(name) and (is_binary(node) or is_nil(node)) do
    %__MODULE__{
      id: id,
      name: name,
      node: node,
      message: message
    }
  end
end
