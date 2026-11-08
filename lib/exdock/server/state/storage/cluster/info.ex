defmodule Exdock.Server.State.Storage.Cluster.Info do
  alias Exdock.Server.State.Storage
  alias Exdock.Domain
  alias Exdock.Server.State.Storage.Cluster.Utils.NodeStorage

  defstruct [
    :by_node_string,
    :info
  ]

  @type t :: %__MODULE__{
          by_node_string: %{String.t() => __MODULE__.InfoData.t()},
          info: __MODULE__.InfoData.t()
        }

  @spec new(map()) :: t()
  def new(%{storage: %NodeStorage{} = storage} = cluster) do
    # Precompute both per-node and aggregate summaries because LiveViews render both levels frequently.
    nodes = storage |> Storage.Nodes.list()
    by_node_string = Map.new(nodes, &{to_string(&1), for_node(cluster, &1)})

    %__MODULE__{
      by_node_string: by_node_string,
      info: new_info_data(storage |> Storage.Containers.list(), storage |> Storage.Images.list())
    }
  end

  @spec for_node(map(), String.t()) :: __MODULE__.InfoData.t()
  def for_node(%{storage: %NodeStorage{} = storage}, node)
      when is_binary(node) do
    c_list = storage |> Storage.Containers.list_node(node)
    i_list = storage |> Storage.Images.list_node(node)
    new_info_data(c_list, i_list)
  end

  @spec new_info_data([Domain.Container.t()], [Domain.Image.t()]) :: __MODULE__.InfoData.t()
  defp new_info_data(containers, images), do: __MODULE__.InfoData.new(containers, images)
end
