defmodule ExdockWeb.PageLive.HomepageLive.Utils.Container do
  alias Exdock.ReadModel.Container
  alias Exdock.ReadModel.Container.Key

  @spec get_container_extended(map(), String.t(), Key.t()) ::
          Container.extended()
  def get_container_extended(extended_map, node, key) when is_map(extended_map) do
    get_container_extended(extended_map |> Map.get(node, %{}), key)
  end

  @spec get_container_extended(%{Key.t() => Container.extended()}, Key.t()) ::
          Container.extended()
  def get_container_extended(extended_map, key) when is_map(extended_map) do
    case Map.get(extended_map, key) do
      nil -> Container.empty_extended()
      ext -> ext
    end
  end
end
