defmodule ExdockWeb.ContainersLive.ContainerGroups do
  @moduledoc false

  alias Exdock.ReadModel.Container
  alias ExdockWeb.PageLive.HomepageLive.Utils.Container, as: ContainerLookup

  @type group_name :: :unknown | :outdated | :ok | :stopped
  @type row :: {Container.Key.t(), Container.Core.t(), Container.Extended.t()}
  @type t :: %{required(group_name()) => [row()]}

  @spec build(map(), map()) :: t()
  def build(containers, containers_extended) do
    containers
    |> Enum.reduce(empty_groups(), fn {key, core}, groups ->
      row = {key, core, ContainerLookup.get_container_extended(containers_extended, key)}
      Map.update!(groups, group_for(core), &[row | &1])
    end)
    |> Map.new(fn {group, rows} -> {group, Enum.sort_by(rows, &sort_key/1)} end)
  end

  defp empty_groups, do: %{unknown: [], outdated: [], ok: [], stopped: []}

  defp group_for(%{is_running: false}), do: :stopped
  defp group_for(%{image_status: :outdated}), do: :outdated
  defp group_for(%{image_status: :updated}), do: :ok
  defp group_for(_core), do: :unknown

  defp sort_key({key, core, _extended}), do: {-core.settings.priority, key.name}
end
