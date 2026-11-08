defmodule Exdock.Server.State.Storage.Cluster.NodeData do
  alias Exdock.Server.State.Storage.Cluster.Info
  alias Exdock.Server.State.Storage.Cluster.Utils.NodeStorage
  alias Exdock.Server.State.Storage
  alias Exdock.Domain

  defstruct [
    :node,
    :info,
    :containers,
    :images
  ]

  @type t :: %__MODULE__{
          node: String.t(),
          info: Info.InfoData.t(),
          containers: [Domain.Container.t()],
          images: [Domain.Image.t()]
        }

  @spec new(map(), String.t()) :: t()
  def new(%{storage: %NodeStorage{} = storage} = cluster, node)
      when is_binary(node) do
    # NodeData is the detailed page payload: raw lists plus the same summary
    # data used by the homepage.
    containers = storage |> Storage.Containers.list_node(node)
    images = storage |> Storage.Images.list_node(node)
    info = Info.for_node(cluster, node)

    %__MODULE__{
      node: node,
      info: info,
      containers: containers,
      images: images
    }
  end
end
