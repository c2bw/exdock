defmodule Exdock.Protocol.Messages.Update do
  @moduledoc "Validated progress update emitted by an authenticated client."

  defstruct [:node, :id, :name, :data, :data_type]

  @type supported_data_types :: :string
  @type t :: %__MODULE__{
          node: String.t() | nil,
          id: String.t(),
          name: atom(),
          data: term(),
          data_type: supported_data_types()
        }

  @spec new(String.t(), atom(), term(), supported_data_types()) :: t()
  def new(id, name, data, data_type \\ :string)
      when is_binary(id) and is_atom(name) and is_atom(data_type),
      do: %__MODULE__{id: id, name: name, node: nil, data: data, data_type: data_type}

  @spec set_node(t(), String.t()) :: t()
  def set_node(%__MODULE__{} = update, node) when is_binary(node),
    do: %{update | node: node}
end
