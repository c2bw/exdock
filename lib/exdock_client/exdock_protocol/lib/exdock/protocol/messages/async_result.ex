defmodule Exdock.Protocol.Messages.AsyncResult do
  @moduledoc "Validated client data that is not a terminal job result."

  defstruct [:node, :name, :id, :result]

  @type t :: %__MODULE__{
          node: String.t(),
          name: atom(),
          id: String.t(),
          result: term()
        }

  @spec new(String.t(), atom(), String.t(), term()) :: t()
  def new(node, name, id, result)
      when is_binary(node) and is_atom(name) and is_binary(id),
      do: %__MODULE__{node: node, name: name, id: id, result: result}
end
