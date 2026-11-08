defmodule Exdock.ClientLib.Container.SnapshotMapper do
  @moduledoc """
  Maps Docker container summaries and inspect responses to protocol snapshots.
  """

  alias Exdock.Protocol.Snapshot.Container, as: ContainerSnapshot

  @compose_project_label "com.docker.compose.project"

  @spec from_inspect(map(), map()) :: ContainerSnapshot.t()
  def from_inspect(summary, inspect) when is_map(summary) and is_map(inspect) do
    %{
      :Image => image_id,
      :Config => %{:Image => image_tag} = config
    } = inspect

    summary
    |> base_snapshot()
    |> Map.merge(%{
      stack_name: compose_project(config),
      image_tag: image_tag,
      image_id: image_id,
      inspect: inspect
    })
    |> then(&struct!(ContainerSnapshot, &1))
  end

  @spec from_summary(map()) :: ContainerSnapshot.t()
  def from_summary(summary) when is_map(summary) do
    summary
    |> base_snapshot()
    |> Map.merge(%{
      stack_name: nil,
      image_tag: nil,
      image_id: nil,
      inspect: nil
    })
    |> then(&struct!(ContainerSnapshot, &1))
  end

  defp base_snapshot(%{:Names => names, :Id => id, :State => state}) do
    %{
      name: normalize_name(names),
      id: id,
      is_running: state == "running",
      resources: nil
    }
  end

  defp normalize_name(names) do
    names
    |> List.first()
    |> to_string()
    |> String.replace_prefix("/", "")
  end

  defp compose_project(%{:Labels => labels}) when is_map(labels),
    do: Map.get(labels, @compose_project_label, "")

  defp compose_project(_config), do: ""
end
