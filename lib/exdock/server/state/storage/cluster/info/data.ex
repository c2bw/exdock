defmodule Exdock.Server.State.Storage.Cluster.Info.InfoData do
  alias Exdock.Server.State.Storage
  alias Exdock.Domain

  defstruct [
    :containers,
    :images
  ]

  @type t :: %__MODULE__{
          containers: Storage.Containers.Info.t(),
          images: Storage.Images.Info.t()
        }

  @spec new(list(Domain.Container.t()), list(Domain.Image.t())) :: t()
  def new(containers, images) when is_list(containers) and is_list(images) do
    %__MODULE__{
      containers: Storage.Containers.Info.new(containers),
      images: Storage.Images.Info.new(images)
    }
  end
end
