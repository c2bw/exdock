defmodule Exdock.Server.Jobs.Event do
  @moduledoc """
  Typed internal event published by the job dispatcher.

  Job lifecycle consumers subscribe through `Exdock.Server.Jobs.subscribe/0`
  and pattern match this struct instead of depending on positional PubSub
  tuples. Constructors keep every event shape explicit at the publishing
  boundary.
  """

  alias Exdock.Server.Jobs

  @type event_type ::
          :job_started
          | :job_updated
          | :job_finished
          | :job_message
          | :package_started
          | :package_finished

  @enforce_keys [:type]
  defstruct type: nil,
            job: nil,
            package: nil,
            info: nil,
            result: nil,
            update: nil,
            message: nil,
            package_id: nil,
            error: nil

  @type t :: %__MODULE__{
          type: event_type(),
          job: Jobs.Job.t() | nil,
          package: Jobs.Package.t() | nil,
          info: Jobs.Info.t() | nil,
          result: Jobs.Result.t() | nil,
          update: Jobs.Update.t() | nil,
          message: Jobs.Message.t() | nil,
          package_id: String.t() | nil,
          error: term()
        }

  @spec job_started(Jobs.Job.t()) :: t()
  def job_started(%Jobs.Job{} = job), do: %__MODULE__{type: :job_started, job: job}

  @spec job_updated(Jobs.Info.t(), Jobs.Update.t()) :: t()
  def job_updated(%Jobs.Info{} = info, %Jobs.Update{} = update),
    do: %__MODULE__{type: :job_updated, info: info, update: update}

  @spec job_finished(Jobs.Info.t(), Jobs.Result.t()) :: t()
  def job_finished(%Jobs.Info{} = info, %Jobs.Result{} = result),
    do: %__MODULE__{type: :job_finished, info: info, result: result}

  @spec job_message(Jobs.Message.t()) :: t()
  def job_message(%Jobs.Message{} = message),
    do: %__MODULE__{type: :job_message, message: message}

  @spec package_started(Jobs.Package.t()) :: t()
  def package_started(%Jobs.Package{} = package),
    do: %__MODULE__{type: :package_started, package: package}

  @spec package_finished(String.t(), term()) :: t()
  def package_finished(package_id, error) when is_binary(package_id),
    do: %__MODULE__{type: :package_finished, package_id: package_id, error: error}
end
