defmodule Exdock.Protocol.Snapshot.Container do
  @moduledoc "Protocol-owned representation of one Docker container snapshot."

  alias Exdock.Protocol.Value

  defstruct [
    :name,
    :id,
    :is_running,
    :stack_name,
    :image_tag,
    :image_id,
    :inspect,
    :resources
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          id: String.t(),
          is_running: boolean(),
          stack_name: String.t() | nil,
          image_tag: String.t() | nil,
          image_id: String.t() | nil,
          inspect: map() | nil,
          resources: map() | nil
        }

  @spec to_wire(t()) :: map()
  def to_wire(%__MODULE__{} = container) do
    %{
      "name" => container.name,
      "id" => container.id,
      "is_running" => container.is_running,
      "stack_name" => container.stack_name,
      "image_tag" => container.image_tag,
      "image_id" => container.image_id,
      "inspect" => Value.encode(container.inspect),
      "resources" => Value.encode(container.resources)
    }
  end

  @spec from_wire(term()) :: {:ok, t()} | {:error, :invalid_container_snapshot}
  def from_wire(%{
        "name" => name,
        "id" => id,
        "is_running" => running,
        "stack_name" => stack,
        "image_tag" => tag,
        "image_id" => image_id,
        "inspect" => inspect,
        "resources" => resources
      })
      when is_binary(name) and is_binary(id) and is_boolean(running) and
             is_map(inspect) and (is_map(resources) or is_nil(resources)) do
    {:ok,
     %__MODULE__{
       name: name,
       id: id,
       is_running: running,
       stack_name: stack,
       image_tag: tag,
       image_id: image_id,
       inspect: inspect,
       resources: resources
     }}
  end

  def from_wire(_payload), do: {:error, :invalid_container_snapshot}
end
