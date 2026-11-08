defmodule Exdock.Server.Logging.Status.JobBehaviour do
  @moduledoc """
  Behaviour and defaults for job-specific status adapters.

  Dashboard callbacks accept their values directly; callers never need to
  retrieve and invoke a second function dynamically.
  """

  alias Exdock.Server.Logging.Status
  alias Exdock.Server.Logging.Status.{Lifecycle, TrackedJob}
  alias Exdock.Server.Jobs.Payload

  @callback data_init(Payload.job_data()) :: TrackedJob.data()
  @callback log(Payload.job_data()) :: {Payload.message(), keyword()} | false
  @callback add(Status.t(), Lifecycle.t()) :: Status.t()
  @callback update(Status.t(), Lifecycle.t()) :: Status.t()
  @callback result(Status.t(), Lifecycle.t()) :: Status.t()
  @callback update_effects(Status.t(), Lifecycle.t()) :: [Status.effect()]
  @callback result_effects(Status.t(), Lifecycle.t()) :: [Status.effect()]
  @callback dash_key(String.t(), Lifecycle.location(), TrackedJob.data()) :: Payload.message()
  @callback dash_data(TrackedJob.data()) :: Payload.message() | nil
  @callback completion_log_options(Status.t(), Lifecycle.t()) :: keyword()

  defmacro __using__(_opts) do
    quote do
      @behaviour Exdock.Server.Logging.Status.JobBehaviour

      def update_effects(_status, _lifecycle), do: []
      def result_effects(_status, _lifecycle), do: []
      def completion_log_options(_status, _lifecycle), do: [lazy: true]
      def dash_key(_job_id, location, data), do: {location, data}
      def dash_data(_data), do: nil

      defoverridable update_effects: 2,
                     result_effects: 2,
                     completion_log_options: 2,
                     dash_key: 3,
                     dash_data: 1
    end
  end
end
