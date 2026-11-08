defmodule Exdock.Server.State.Storage.Settings.Importer do
  @moduledoc """
  Builds and executes a validated server-configuration import plan.

  Malformed sections remain independently skippable for compatibility. Valid
  sections are planned completely before the transactional executor performs
  any purge or write.
  """

  require Logger

  alias Exdock.Configuration
  alias Exdock.Database
  alias Exdock.Server.State.Storage.Settings.Importer.{Executor, Plan, Report}

  @spec import(Configuration.t() | String.t()) :: {:ok, Report.t()} | {:error, term()}
  def import(%Configuration{} = configuration) do
    plan =
      configuration
      |> Configuration.import_sections()
      |> Plan.build(known_nodes())

    Enum.each(plan.warnings, &log_warning/1)

    case Executor.execute(plan) do
      :ok -> {:ok, Report.from_plan(plan)}
      {:error, _reason} = error -> error
    end
  end

  def import(json_string) when is_binary(json_string) do
    case Configuration.from_json(json_string) do
      {:ok, configuration} -> __MODULE__.import(configuration)
      {:error, "expected an object"} -> {:error, :invalid_top_level_configuration}
      {:error, reason} -> {:error, reason}
    end
  end

  defp known_nodes do
    Database.Nodes.load_all()
    |> MapSet.new(& &1.node)
  end

  defp log_warning({:invalid_section, label}),
    do: Logger.error("Settings: unexpected #{label} format for import.")

  defp log_warning({:unknown_node, node}),
    do: Logger.warning("Settings: skipping import for unknown node #{inspect(node)}.")
end
