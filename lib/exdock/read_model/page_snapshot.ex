defmodule Exdock.ReadModel.PageSnapshot do
  @moduledoc """
  Aggregates runtime and activity snapshots at the read-model boundary.

  Runtime and logging state have independent owners and revisions. Reading each
  owner from the caller avoids nesting a logging call inside the runtime
  coordinator while preserving one page-shaped response.
  """

  alias Exdock.Runtime.Coordinator
  alias Exdock.Server.Logging

  @spec build([atom()]) :: map()
  def build(projections) when is_list(projections) do
    runtime = Coordinator.query({:page, projections})
    Map.merge(runtime, activity())
  end

  @spec build_node(String.t(), [atom()]) :: {map(), Exdock.ReadModel.Node.t() | :not_found}
  def build_node(node, projections) when is_binary(node) and is_list(projections) do
    %{page: runtime, node: node_detail} =
      Coordinator.query({:node_page, node, projections})

    {Map.merge(runtime, activity()), node_detail}
  end

  @spec activity() :: %{
          activity_revision: non_neg_integer(),
          status: Exdock.Server.Logging.Status.t(),
          log: [Exdock.Server.Logging.Log.t()]
        }
  def activity do
    %{revision: revision, status: status, log: log} = Logging.snapshot()
    %{activity_revision: revision, status: status, log: log}
  end
end
