defmodule Exdock.Server.Logging.Status.ContainerRecreate do
  use Exdock.Server.Logging.Status.ContainerAction,
    action_label: "Recreate Container",
    error_action: "recreate",
    recreate: true

  alias Exdock.Server.Logging.Status.Utils

  @impl true
  def result(status, %Lifecycle{data: %{"container" => container, "warning" => warning}, error: nil} = lifecycle)
      when is_binary(container) and is_binary(warning) do
    status
    |> super(%{lifecycle | data: container})
    |> Utils.add_entry_to_errors_log("Warning: #{warning}", lifecycle.occurred_at)
    |> Utils.set_job_message("Recreate Container", "Recreated [#{container}] on [#{lifecycle.node}]. Warning: #{warning}")
  end

  def result(status, lifecycle), do: super(status, lifecycle)
end
