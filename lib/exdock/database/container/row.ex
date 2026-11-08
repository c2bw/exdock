defmodule Exdock.Database.Container.Row do
  @moduledoc false

  use Ecto.Schema

  @image_status [:unknown, :updated, :outdated, :empty_local_digest, :empty_remote_digest]

  @type t :: %__MODULE__{}

  @primary_key false
  schema "containers" do
    field :node, :string, primary_key: true, autogenerate: false
    field :name, :string, primary_key: true, autogenerate: false
    field :image_key, :string
    field :id, :string
    field :is_running, :boolean
    field :stack_name, :string
    field :configuration, Exdock.Encrypted.Binary
    field :state, :string
    field :image_tag, :string
    field :image_id, :string
    field :image_status, Ecto.Enum, values: @image_status
    field :is_deleted, :boolean
  end
end
