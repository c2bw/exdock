defmodule Exdock.Database.Container.Changeset do
  @moduledoc false

  import Ecto.Changeset

  alias Exdock.Database
  alias Exdock.Database.Container.Row

  @cast_fields [
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

  @required_fields [
    :node,
    :name,
    :id,
    :is_running,
    :configuration,
    :state,
    :image_tag,
    :image_id,
    :image_status,
    :is_deleted
  ]

  @spec build(map()) :: Ecto.Changeset.t()
  def build(stored_row) when is_map(stored_row) do
    %Row{}
    |> cast(stored_row, @cast_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:node, :name])
    |> put_image_key()
    |> foreign_key_constraint(:image_key)
  end

  defp put_image_key(changeset) do
    case {get_field(changeset, :node), get_field(changeset, :image_id)} do
      {node, image_id} when is_binary(node) and is_binary(image_id) ->
        put_change(changeset, :image_key, Database.Image.generate_key(node, image_id))

      _invalid_identity ->
        changeset
    end
  end
end
