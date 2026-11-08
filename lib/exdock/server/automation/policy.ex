defmodule Exdock.Server.Automation.Policy do
  @moduledoc """
  Pure decisions for periodic automation and schedule changes.

  Runtime commands and operation events are returned as data for the automation
  handler. Persisted schedule mutations remain explicit for the owning facade.
  """

  alias Exdock.Domain
  alias Exdock.Runtime.{Command, Mutation}
  alias Exdock.Server.State
  alias Exdock.Server.State.Storage

  @type effect ::
          {:command, Ecto.UUID.t() | nil, Command.internal_t(), keyword()}
          | {:operation_finished, Ecto.UUID.t(), atom(), map()}

  @type schedule_decision ::
          {:commit, State.t(), Mutation.t()}
          | {:reject, State.t()}

  @spec run(State.t(), Ecto.UUID.t() | nil) :: {State.t(), [effect()]}
  def run(%State{settings: settings} = state, operation_id)
      when is_binary(operation_id) or is_nil(operation_id) do
    effects =
      settings
      |> Storage.Settings.get()
      |> command_effects()
      |> Kernel.++(completion_effects(operation_id))

    {State.periodic_job_rollover(state), effects}
  end

  @spec change_schedule(State.t(), String.t()) :: schedule_decision()
  def change_schedule(%State{periodic_job: current_job} = state, cron) when is_binary(cron) do
    case State.PeriodicJob.replace(current_job, cron) do
      {:ok, next_job} ->
        {:commit, %{state | periodic_job: next_job}, Storage.Settings.Change.cron(cron)}

      {:error, unchanged_job} ->
        {:reject, %{state | periodic_job: unchanged_job}}
    end
  end

  defp command_effects(%Domain.UserSettings{automation_enabled: false}), do: []

  defp command_effects(%Domain.UserSettings{} = settings) do
    [container_or_registry_effect(settings)] ++ release_effects(settings)
  end

  defp container_or_registry_effect(%Domain.UserSettings{auto_update_containers: true}),
    do: {:command, nil, State.Jobs.compose(:containers_update), []}

  defp container_or_registry_effect(%Domain.UserSettings{}),
    do: {:command, nil, State.Jobs.compose(:registry_update), []}

  defp release_effects(%Domain.UserSettings{auto_update_releases: true}) do
    [{:command, nil, Command.Repository.fetch_releases([:ok, :rate_limit]), [automated: true]}]
  end

  defp release_effects(%Domain.UserSettings{}), do: []

  defp completion_effects(nil), do: []

  defp completion_effects(operation_id) when is_binary(operation_id) do
    [{:operation_finished, operation_id, :run_automation, %{status: :completed}}]
  end
end
