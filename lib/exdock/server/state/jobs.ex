defmodule Exdock.Server.State.Jobs do
  @moduledoc """
  Converts state-aware job requests into normalized job plans.

  This module expands named workflows from authoritative state. Operation
  correlation, automation policy, and dispatcher delivery are owned by
  `Exdock.Server.Jobs.Plan` and `Exdock.Server.Jobs.Submission`.
  """

  alias Exdock.Domain
  alias Exdock.Server.State
  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.Detail
  alias Exdock.Server.Jobs.Plan
  alias Exdock.Runtime.Command.Workflow
  alias Exdock.Server.State.Storage.Cluster
  alias Exdock.Server.State.Storage.Settings
  alias Exdock.Server.State.Storage.Containers

  @flow_steps %{
    registry_update: [:node_refresh, :registry_fetch],
    containers_update: [:node_refresh, :registry_fetch, :containers_update]
  }

  @type automation_flow :: :registry_update | :containers_update
  @type composed_step :: Workflow.step()

  @doc """
    Compose high-level automation flows from smaller job macros.

    Registry-only automation refreshes nodes after registry metadata is fetched.
    Container-update automation then recreates eligible outdated containers.
  """
  @spec compose(automation_flow()) :: Workflow.t()
  def compose(flow) do
    {:compose, step, remaining} = initial_composed_payload(flow)
    Workflow.new(step, remaining)
  end

  defp initial_composed_payload(flow) do
    [first_step | remaining_steps] = Map.fetch!(@flow_steps, flow)
    {:compose, first_step, remaining_steps}
  end

  @spec build(State.t(), Workflow.t()) :: Plan.t()
  def build(%State{} = state, %Workflow{step: current_step, remaining: remaining_steps}) do
    # Compose stores only the remaining steps in the job callback.
    # Each step is rebuilt from fresh state after the previous step completes.
    state
    |> compose_job(current_step, remaining_steps)
    |> Plan.new()
    |> Plan.automated(true)
  end

  # Build one composed step, and if it is a detail attach the continuation.
  # The callback is where chain behavior is enforced (only success triggers the
  # next step).
  @spec compose_job(State.t(), composed_step(), list(composed_step())) :: Plan.source()
  defp compose_job(%State{} = state, this_step, next_steps) do
    with %Detail{} = this_job <- build_step(state, this_step) do
      chain_next_step(this_job, next_steps)
    end
  end

  defp chain_next_step(%Detail{} = current_job, []), do: Detail.set_automated(current_job)

  defp chain_next_step(%Detail{} = current_job, [next_step | remaining_steps]),
    do:
      current_job
      |> Detail.set_continuation(Workflow.new(next_step, remaining_steps))
      |> Detail.set_automated()

  defp auto_update_recreate_requests(%State{} = state, storage) do
    %Domain.UserSettings{auto_update_above: update_above} = Settings.get(state.settings)

    storage
    |> Containers.list()
    # The auto-update threshold is evaluated from this cluster snapshot so only
    # currently eligible containers are recreated.
    |> Enum.filter(&Domain.Container.can_auto_update?(&1, update_above))
    |> Enum.map(&container_recreate_request/1)
  end

  defp container_recreate_request(%Domain.Container{node: node, name: name} = container) do
    %{node: node, container: name, img_tag: Domain.Container.image_tag(container)}
  end

  defp build_step(%State{} = state, :node_refresh), do: Jobs.Client.Node.refresh_cluster(state, :normal)
  defp build_step(%State{} = state, :registry_fetch), do: Jobs.Local.Registry.fetch_cluster(state)

  defp build_step(%State{} = state, :containers_update) do
    %State{cluster: %Cluster{storage: storage}} = state
    recreate_requests = auto_update_recreate_requests(state, storage)

    Exdock.Server.Jobs.Client.Container.recreate(
      state,
      Enum.map(recreate_requests, &{&1.node, &1.container}),
      true
    )
  end
end
