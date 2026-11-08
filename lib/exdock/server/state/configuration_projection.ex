defmodule Exdock.Server.State.ConfigurationProjection do
  @moduledoc """
  Projects authoritative runtime state into the public configuration boundary.

  Keeping state traversal here leaves `Exdock.Configuration` independent of
  runtime storage and prevents the configuration DTO from participating in
  state/settings dependency cycles.
  """

  alias Exdock.Configuration
  alias Exdock.ReadModel.Value
  alias Exdock.Server.State
  alias Exdock.Server.State.Storage
  alias Exdock.Domain

  @spec from_state(State.t()) :: Configuration.t()
  def from_state(%State{} = state) do
    %Configuration{
      user_settings: state.settings |> Storage.Settings.get() |> Value.project(),
      nodes_settings: collect_node_settings(state),
      images_settings: collect_image_settings(state),
      containers_settings: collect_container_settings(state),
      repository_overrides: collect_repository_overrides(state)
    }
  end

  defp collect_node_settings(%State{} = state) do
    state
    |> Storage.Nodes.full_string_map()
    |> map_node_values(&extract_node_settings/1)
  end

  defp collect_image_settings(%State{} = state) do
    state
    |> Storage.Images.full_string_map()
    |> map_node_values(&extract_image_settings/1)
  end

  defp collect_container_settings(%State{} = state) do
    state
    |> Storage.Containers.full_string_map()
    |> map_node_values(&extract_container_settings/1)
  end

  defp collect_repository_overrides(%State{} = state) do
    state
    |> Storage.Images.full_string_map()
    |> flatten_grouped_values()
    |> Enum.filter(&repository_override?/1)
    |> Map.new(fn %Domain.Image{name: name, metadata: metadata} -> {name, Value.project(metadata)} end)
  end

  defp repository_override?(%Domain.Image{name: name, metadata: metadata}) do
    metadata != Domain.Image.Metadata.default(name)
  end

  defp map_node_values(node_values, mapper)
       when is_map(node_values) and is_function(mapper, 1) do
    Map.new(node_values, fn {node, value} -> {node, mapper.(value)} end)
  end

  defp extract_node_settings(%Domain.Node{settings: settings}), do: Value.project(settings)

  defp extract_image_settings(images) when is_list(images) do
    Map.new(images, fn %Domain.Image{id: id, settings: settings} -> {id, Value.project(settings)} end)
  end

  defp extract_container_settings(containers) when is_list(containers) do
    Map.new(containers, fn %Domain.Container{name: name, core: %{settings: settings}} ->
      {name, Value.project(settings)}
    end)
  end

  defp flatten_grouped_values(node_groups) when is_map(node_groups) do
    node_groups
    |> Map.values()
    |> Enum.flat_map(& &1)
  end
end
