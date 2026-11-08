defmodule Exdock.Database.Container.Record do
  @moduledoc "Decoded container persistence data used outside the Ecto schema boundary."

  defstruct [
    :node,
    :name,
    :id,
    :is_running,
    :stack_name,
    :configuration,
    :state,
    :image_tag,
    :image_id,
    :image_status,
    :is_deleted
  ]

  @type t :: %__MODULE__{
          node: String.t(),
          name: String.t(),
          id: String.t(),
          is_running: boolean(),
          stack_name: String.t() | nil,
          configuration: map(),
          state: map(),
          image_tag: String.t(),
          image_id: String.t(),
          image_status: atom(),
          is_deleted: boolean()
        }
end
