defmodule Exdock.Runtime.Query do
  @moduledoc false

  alias Exdock.Server.State
  alias Exdock.Server.State.ConfigurationProjection
  alias Exdock.Server.State.Storage
  alias Exdock.Runtime.Query.ProjectionInput
  alias Exdock.Runtime.Projection
  alias Exdock.ReadModel.{Projections, Value}

  @type t ::
          {:page, [Projections.key()]}
          | {:node_page, String.t(), [Projections.key()]}
          | :periodic_job

  @type result ::
          map()
          | Exdock.Server.State.PeriodicJob.t()
          | nil

  @spec run(State.t(), t()) :: result()
  def run(%State{} = state, {:page, projections}) when is_list(projections) do
    page(state, projections)
  end

  def run(%State{} = state, {:node_page, node, projections})
      when is_binary(node) and is_list(projections) do
    %{
      page: page(state, projections),
      node: node_projection(state, node)
    }
  end

  def run(%State{} = state, :periodic_job), do: state.periodic_job

  defp page(%State{} = state, projections) do
    validate_projections!(projections)

    projections
    |> Enum.reduce(base_page(state), fn projection, page ->
      input = ProjectionInput.for(projection, state)
      Map.merge(page, Projections.query_assigns(projection, input))
    end)
  end

  defp node_projection(%State{} = state, node) do
    case Storage.Cluster.data(state, node) do
      :not_found -> :not_found
      node_data -> Projection.node(node_data)
    end
  end

  defp base_page(state) do
    %{
      runtime_revision: state.revision || 0,
      server_configuration: ConfigurationProjection.from_state(state),
      user_settings: state.settings |> Storage.Settings.get() |> Value.project(),
      nodes_list: Storage.Nodes.ordered_list(state)
    }
  end

  defp validate_projections!(projections) do
    case Projections.unknown_keys(projections) do
      [] -> :ok
      unknown -> raise ArgumentError, "unknown read-model projections: #{inspect(unknown)}"
    end
  end
end
