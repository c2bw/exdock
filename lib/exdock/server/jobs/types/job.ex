defmodule Exdock.Server.Jobs.Job do
  @moduledoc """
  Runtime representation of an executable job.

  `Detail` is the queued request; `Job` is the concrete unit selected by the
  dispatcher after gatekeeping. Jobs can run locally or be sent to remote nodes,
  and may be marked `:linked` when equivalent work is already running.
  """

  alias Exdock.Server.Jobs.Job.{Local, Remote}
  alias Exdock.Server.Jobs.Spec
  alias Exdock.Server.Jobs.Detail
  alias Exdock.Server.Jobs.Payload

  defstruct [
    :type,
    :status,
    :id,
    :name,
    :is_automated,
    :parameters,
    :data,
    :refresh_generation
  ]

  @type job_status :: :none | :linked | :running | :terminated
  @type t :: %__MODULE__{
          type: Local.t() | Remote.t(),
          status: job_status(),
          id: String.t(),
          name: atom(),
          is_automated: boolean(),
          parameters: [Payload.parameter()],
          data: Payload.job_data(),
          refresh_generation: pos_integer() | nil
        }

  @doc """
  Create a runtime job from a queued detail and executable spec.
  """
  @spec new(Detail.t(), Spec.t()) :: t()
  def new(%Detail{} = detail, %Spec{} = spec), do: from_detail_and_spec(detail, spec, type_from_spec(spec))

  defp type_from_spec(%Spec{location: %Spec.Local{function: function}}), do: Local.new(function)
  defp type_from_spec(%Spec{location: %Spec.Remote{nodes: nodes}}), do: Remote.new(nodes)

  @spec from_detail_and_spec(Detail.t(), Spec.t(), Remote.t() | Local.t()) :: t()
  defp from_detail_and_spec(
         %Detail{id: id, name: name, is_automated: is_automated},
         %Spec{parameters: parameters, data: data},
         type
       ) do
    %__MODULE__{
      type: type,
      status: :none,
      id: id,
      name: name,
      is_automated: is_automated,
      parameters: parameters,
      data: data
    }
  end

  @spec set_status(t(), job_status()) :: t()
  def set_status(%__MODULE__{} = job, status) when is_atom(status) do
    %{job | status: status}
  end

  @spec set_linked(t()) :: t()
  def set_linked(%__MODULE__{} = job), do: %{job | status: :linked}

  @doc """
  Set the job status to `:running` only if it has not been linked or terminated.
  """
  @spec set_running(t()) :: t()
  def set_running(%__MODULE__{status: :none} = job), do: %{job | status: :running}
  def set_running(%__MODULE__{} = job), do: job

  @spec linked?(t()) :: boolean()
  def linked?(%__MODULE__{status: :linked}), do: true
  def linked?(%__MODULE__{}), do: false

  @spec locations(t()) :: list(String.t())
  def locations(%__MODULE__{type: %Remote{nodes: nodes}}), do: nodes
  def locations(%__MODULE__{type: %Local{}}), do: []
end
