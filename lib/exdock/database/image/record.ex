defmodule Exdock.Database.Image.Record do
  @moduledoc "Decoded image persistence data used outside the Ecto schema boundary."

  @fields [:node, :id, :name, :tags, :digest, :size, :shared_size, :build_date, :repo_digests]

  defstruct (@fields -- [:repo_digests]) ++ [repo_digests: []]

  @spec fields() :: [atom()]
  def fields, do: @fields

  @type t :: %__MODULE__{
          node: Exdock.NodeId.t(),
          id: String.t(),
          name: String.t(),
          tags: [String.t()],
          digest: String.t() | nil,
          repo_digests: [String.t()],
          size: integer(),
          shared_size: integer(),
          build_date: DateTime.t()
        }
end
