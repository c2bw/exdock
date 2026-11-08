defmodule Exdock.Server.Jobs.PublisherBehaviour do
  @moduledoc "Contract used by the Jobs runtime to publish dispatcher lifecycle events."

  alias Exdock.Server.Jobs

  @callback subscribe_to_node_changes(atom()) :: :ok | {:error, term()}
  @callback package_started(Jobs.Package.t() | term(), keyword()) :: :ok
  @callback job_started(Jobs.Job.t(), keyword()) :: :ok
  @callback job_finished(Jobs.Info.t(), Jobs.Result.t(), keyword()) :: :ok
  @callback job_message(Jobs.Message.t(), keyword()) :: :ok
  @callback running_job_event(Jobs.State.t(), atom(), String.t(), term(), keyword()) :: :ok
  @callback package_finished(String.t(), term(), keyword()) :: :ok
  @callback terminal_operation(Jobs.Info.t() | nil, Jobs.State.t(), Jobs.Result.t(), keyword()) :: :ok
end
