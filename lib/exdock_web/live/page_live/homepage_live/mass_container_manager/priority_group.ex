defmodule ExdockWeb.HomepageLive.MassContainerManager.PriorityGroup do
  @moduledoc false

  alias Exdock.ReadModel.{Container, Image}

  defstruct [:priority, :containers, :recreate_jobs, :pull_jobs, :image_size]

  @type container :: {String.t(), Container.Key.t(), Container.Core.t()}
  @type t :: %__MODULE__{
          priority: integer(),
          containers: [container()],
          recreate_jobs: [map()],
          pull_jobs: [map()],
          image_size: non_neg_integer()
        }

  @spec from_snapshot(%{String.t() => [map()]}) :: [t()]
  def from_snapshot(containers_by_node) do
    containers_by_node
    |> Enum.flat_map(fn {node, containers} ->
      Enum.flat_map(containers, fn
        %{core: %{image_status: :outdated, is_running: true} = core} = container ->
          [{node, Container.key(container), core}]

        _container ->
          []
      end)
    end)
    |> Enum.group_by(fn {_node, _key, core} -> core.settings.priority end)
    |> Enum.sort_by(fn {priority, _containers} -> priority end, :desc)
    |> Enum.map(&build/1)
  end

  @spec build_all([{integer(), [container()]}] | [t()]) :: [t()]
  def build_all(groups), do: Enum.map(groups, &build/1)

  @spec build({integer(), [container()]} | t()) :: t()
  def build(%__MODULE__{} = group), do: group

  def build({priority, containers}) do
    {pull_jobs, image_size} = image_projection(containers)

    %__MODULE__{
      priority: priority,
      containers: containers,
      recreate_jobs: Enum.map(containers, &recreate_job/1),
      pull_jobs: pull_jobs,
      image_size: image_size
    }
  end

  defp image_projection(containers) do
    {jobs, size, _seen} =
      Enum.reduce(containers, {[], 0, MapSet.new()}, fn {node, _key, core}, {jobs, size, seen} ->
        image_key = {node, Image.normalize_tag(core.image_tag)}

        if MapSet.member?(seen, image_key) do
          {jobs, size, seen}
        else
          job = %{node: node, image_tag: core.image_tag}
          {[job | jobs], size + core.image_size, MapSet.put(seen, image_key)}
        end
      end)

    {Enum.reverse(jobs), size}
  end

  defp recreate_job({node, key, _core}), do: %{node: node, name: key.name}
end
