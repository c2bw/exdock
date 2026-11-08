defmodule Exdock.Server.Connection.WireMessage do
  @moduledoc """
  Validated client payload that has not yet been coupled to server job types.

  The connection protocol produces this transport DTO. The session boundary
  converts it to the internal message understood by state and job reducers.
  """

  @type message_type :: :progress | :result | :resource_sample

  @enforce_keys [:type, :node]
  defstruct [:type, :id, :kind, :node, :data, :error]

  @type t :: %__MODULE__{
          type: message_type(),
          id: String.t(),
          kind: String.t() | nil,
          node: String.t(),
          data: term(),
          error: term()
        }

  @spec progress(String.t(), String.t(), String.t(), term()) :: t()
  def progress(id, kind, node, data)
      when is_binary(id) and is_binary(kind) and is_binary(node),
      do: %__MODULE__{type: :progress, id: id, kind: kind, node: node, data: data}

  @spec result(String.t(), String.t(), String.t(), term(), term()) :: t()
  def result(id, kind, node, data, error)
      when is_binary(id) and is_binary(kind) and is_binary(node),
      do: %__MODULE__{type: :result, id: id, kind: kind, node: node, data: data, error: error}

  @spec resource_sample(String.t(), String.t(), term()) :: t()
  def resource_sample(node, container_id, sample)
      when is_binary(node) and is_binary(container_id),
      do: %__MODULE__{type: :resource_sample, id: container_id, node: node, data: sample}
end
