defmodule Exdock.Database.Image.Changeset do
  @moduledoc false

  import Ecto.Changeset

  alias Exdock.Database.Image.Mapper
  alias Exdock.Database.Image.Row

  @persisted_fields [:node, :id, :name, :tags, :digest, :size, :shared_size, :build_date, :repo_digests]
  @required_fields [:id, :node, :name, :size, :shared_size, :build_date]

  @spec build(map()) :: Ecto.Changeset.t()
  def build(stored_row) when is_map(stored_row) do
    %Row{}
    |> cast(stored_row, @persisted_fields, empty_values: [])
    |> validate_required(@required_fields)
    |> truncate_build_date()
    |> unique_constraint([:node, :id])
    |> put_image_key()
  end

  defp put_image_key(changeset) do
    case {get_field(changeset, :node), get_field(changeset, :id)} do
      {node, id} when is_binary(node) and is_binary(id) ->
        put_change(changeset, :image_key, Mapper.key(node, id))

      _invalid_identity ->
        changeset
    end
  end

  defp truncate_build_date(changeset) do
    case get_field(changeset, :build_date) do
      nil -> changeset
      build_date -> put_change(changeset, :build_date, DateTime.truncate(build_date, :second))
    end
  end
end
