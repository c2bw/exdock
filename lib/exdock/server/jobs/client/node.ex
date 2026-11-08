defmodule Exdock.Server.Jobs.Client.Node do
  @moduledoc """
  Builds remote node-refresh jobs.

  A refresh asks connected clients for their Docker containers/images and, when
  enabled, schedules resource sampling. The result becomes the authoritative
  cluster snapshot for each refreshed node.
  """

  alias Exdock.Server.State.Storage.Settings
  alias Exdock.Server.State.Storage.Containers
  alias Exdock.Server.State.Storage
  alias Exdock.Server.State
  alias Exdock.Domain
  alias Exdock.Server.Jobs.Spec
  alias Exdock.Server.Jobs.Detail
  alias Exdock.Server.Jobs.Payload.NodeRefresh

  @type log_condition :: :normal | :hidden | :no
  @typep refresh_context :: %{
           containers: %{String.t() => list(Domain.Container.t())},
           settings: Domain.UserSettings.t()
         }

  @doc """
  Refresh all nodes currently present in cluster storage.
  """
  @spec refresh_cluster(State.t(), log_condition()) :: Detail.t() | nil
  def refresh_cluster(%State{cluster: %Storage.Cluster{storage: storage}} = state, log \\ :normal) when is_atom(log) do
    storage
    |> Storage.Nodes.list()
    |> build_refresh_work(state, log)
  end

  @doc """
  Refresh a specific node when it is present in cluster storage.
  """
  @spec refresh_node(State.t(), String.t(), log_condition()) :: Detail.t() | nil
  def refresh_node(%State{cluster: %Storage.Cluster{storage: storage}} = state, node, log \\ :normal)
      when is_binary(node) and is_atom(log) do
    storage
    |> Storage.Nodes.get(node)
    |> build_refresh_work_for_node(state, log)
  end

  defp build_refresh_work(nodes, %State{} = state, log)
       when is_list(nodes) and is_atom(log) do
    case Enum.uniq(nodes) do
      [] -> nil
      refreshed_nodes -> build_refresh_detail(refreshed_nodes, refresh_context(state), log)
    end
  end

  defp build_refresh_work_for_node(nil, _state, _log), do: nil

  defp build_refresh_work_for_node(%Domain.Node{node: node}, %State{} = state, log),
    do: build_refresh_work([node], state, log)

  @spec build_refresh_detail(
          list(String.t()),
          refresh_context(),
          atom()
        ) :: Detail.t()
  defp build_refresh_detail(
         nodes,
         %{containers: containers, settings: %Domain.UserSettings{container_resources: resources}},
         log
       )
       when is_list(nodes) do
    nodes = Enum.map(nodes, &to_string/1)

    # Initial container state is included so status logging can compare before
    # and after refresh, for example to detect restarted containers.
    initial_container_state = containers_before_refresh(nodes, containers)

    Detail.new(
      :node_refresh,
      Spec.new(
        Spec.Remote.new(nodes),
        refresh_job_parameters(resources),
        refresh_job_data(nodes, initial_container_state, log)
      )
    )
  end

  defp refresh_context(%State{} = state) do
    %{
      containers: Containers.full_string_map(state),
      settings: Settings.get(state.settings)
    }
  end

  defp refresh_job_parameters(resources), do: [refresh_options(resources)]
  defp refresh_options(retrieve_resources), do: %{"retrieve_resources" => retrieve_resources}

  defp refresh_job_data(nodes, before_refresh, log) do
    NodeRefresh.new(
      before_refresh,
      refresh_log_payload(nodes, log),
      refresh_log_options(log)
    )
  end

  defp refresh_log_options(log), do: [hidden: log == :hidden]

  defp refresh_log_payload(_nodes, :no), do: nil
  defp refresh_log_payload(nodes, _log), do: %{nodes: nodes, containers: %{}}

  @spec containers_before_refresh(list(String.t()), %{String.t() => list(Domain.Container.t())}) :: map()
  defp containers_before_refresh(nodes, containers) when is_list(nodes) do
    Map.new(nodes, &{&1, container_states_before(containers, &1)})
  end

  @spec container_states_before(%{String.t() => list(Domain.Container.t())}, String.t()) ::
          [{String.t(), {:before, boolean()}}]
  defp container_states_before(containers, node) when is_binary(node) do
    containers
    |> Map.get(node, [])
    |> Enum.map(&container_before_refresh/1)
  end

  # Status logging only needs the stable container name and whether it was
  # running before the remote refresh replaces the node snapshot.
  @spec container_before_refresh(Domain.Container.t()) :: {String.t(), {:before, boolean()}}
  defp container_before_refresh(%Domain.Container{name: name} = container),
    do: {name, {:before, Domain.Container.running?(container)}}
end
