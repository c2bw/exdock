defmodule Exdock.Database.Image.Row do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key false
  schema "images" do
    field :node, :string, primary_key: true, autogenerate: false
    field :id, :string, primary_key: true, autogenerate: false
    field :image_key, :string
    field :name, :string
    field :tags, :string
    field :digest, :string
    field :repo_digests, {:array, :string}, default: []
    field :size, :integer
    field :shared_size, :integer
    field :build_date, :utc_datetime
  end
end
