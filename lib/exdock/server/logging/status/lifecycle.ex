defmodule Exdock.Server.Logging.Status.Lifecycle do
  @moduledoc """
  Typed context passed to job-specific status lifecycle callbacks.

  Keeping lifecycle metadata in one value prevents the status callback contract
  from growing positional arguments as new job metadata is introduced.
  """

  alias Exdock.Server.Logging.Status.JobRegistry
  alias Exdock.Server.Jobs.Payload

  @enforce_keys [:phase, :job_name, :job_id, :data, :occurred_at]
  defstruct [:phase, :job_name, :job_id, :node, :locations, :data, :error, :occurred_at]

  @type phase :: :started | :updated | :finished
  @type location :: Exdock.NodeId.t() | :local

  @type t :: %__MODULE__{
          phase: phase(),
          job_name: JobRegistry.job_name(),
          job_id: String.t(),
          node: location() | nil,
          locations: [location()] | nil,
          data: Payload.job_data() | Payload.update() | Payload.result(),
          error: Payload.error(),
          occurred_at: DateTime.t()
        }

  @spec started(JobRegistry.job_name(), String.t(), list(), Payload.job_data(), DateTime.t()) :: t()
  def started(job_name, job_id, locations, data, %DateTime{} = occurred_at)
      when is_atom(job_name) and is_binary(job_id) and is_list(locations) do
    %__MODULE__{
      phase: :started,
      job_name: job_name,
      job_id: job_id,
      locations: locations,
      data: data,
      occurred_at: occurred_at
    }
  end

  @spec updated(
          JobRegistry.job_name(),
          String.t(),
          location() | nil,
          Payload.update(),
          Payload.error(),
          DateTime.t()
        ) :: t()
  def updated(job_name, job_id, node, data, error, %DateTime{} = occurred_at)
      when is_atom(job_name) and is_binary(job_id) do
    %__MODULE__{
      phase: :updated,
      job_name: job_name,
      job_id: job_id,
      node: node,
      data: data,
      error: error,
      occurred_at: occurred_at
    }
  end

  @spec finished(
          JobRegistry.job_name(),
          String.t(),
          location() | nil,
          Payload.result(),
          Payload.error(),
          DateTime.t()
        ) :: t()
  def finished(job_name, job_id, node, data, error, %DateTime{} = occurred_at)
      when is_atom(job_name) and is_binary(job_id) do
    %__MODULE__{
      phase: :finished,
      job_name: job_name,
      job_id: job_id,
      node: node,
      data: data,
      error: error,
      occurred_at: occurred_at
    }
  end
end
