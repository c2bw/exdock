defmodule Exdock.Server.State.Domains.Settings do
  @moduledoc "State transition boundary for settings."

  @behaviour Exdock.Server.State.Change.Behaviour

  alias Exdock.Configuration
  alias Exdock.Runtime.Mutation
  alias Exdock.Runtime.Mutation.Payload.{ConfigurationImport, UserSetting}
  alias Exdock.Server.State
  alias Exdock.Server.State.PeriodicJob
  alias Exdock.Server.State.Change.{Outcome, Plan}
  alias Exdock.Server.State.Storage.Settings

  @impl true
  def reload(%State{} = state), do: state

  @impl true
  def broadcast(%State{settings: %Settings{} = settings}) do
    {Settings.get(settings), []}
  end

  @impl true
  def plan(%State{} = state, %Mutation{action: :user_setting, data: %UserSetting{} = data}) do
    mutation = %Mutation{domain: :settings, action: :user_setting, data: data}
    Plan.persisted(__MODULE__, state, mutation)
  end

  def plan(%State{} = state, %Mutation{action: :import, data: %ConfigurationImport{} = data}) do
    mutation = %Mutation{domain: :settings, action: :import, data: data}
    Plan.persisted(__MODULE__, state, mutation)
  end

  @impl true
  def execute_persisted(
        %State{settings: settings} = state,
        %Mutation{action: :user_setting, data: %UserSetting{key: key, value: value}}
      ) do
    settings
    |> Settings.change_user_setting(key, value)
    |> project_settings_result(state)
  end

  def execute_persisted(
        %State{} = state,
        %Mutation{action: :import, data: %ConfigurationImport{configuration: %Configuration{} = configuration}}
      ) do
    case Settings.import(configuration) do
      {:ok, settings, report} ->
        state
        |> settings_changed(settings)
        |> Map.put(:operation_result, %{status: :completed, import_report: report})

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp project_settings_result(result, state) do
    case result do
      {:ok, settings} -> settings_changed(state, settings)
      {:error, reason} -> {:error, reason}
    end
  end

  defp settings_changed(%State{} = state, %Settings{} = settings) do
    state =
      state
      |> Map.put(:settings, settings)
      |> refresh_periodic_job(settings)

    Outcome.planned(state, [delayed: false, force: true], [])
  end

  defp refresh_periodic_job(
         %State{periodic_job: %PeriodicJob{cron_string: cron_string}} = state,
         %Settings{} = settings
       ) do
    new_cron_string = settings |> Settings.get() |> Map.fetch!(:cron_string)

    if new_cron_string == cron_string do
      state
    else
      case PeriodicJob.replace(state.periodic_job, new_cron_string) do
        {:ok, periodic_job} -> %{state | periodic_job: periodic_job}
        {:error, _periodic_job} -> state
      end
    end
  end

  defp refresh_periodic_job(%State{} = state, %Settings{}), do: state
end
