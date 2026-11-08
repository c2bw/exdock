defmodule Exdock.Server.Jobs.Spec do
  @moduledoc """
  Executable unit inside a job detail.

  A spec describes where work runs, which parameters are sent to the handler, and
  optional opaque data used by callers for display or bookkeeping.
  """

  alias Exdock.Server.Jobs.Spec.{Local, Remote}
  alias Exdock.Server.Jobs.Payload

  defstruct [
    :location,
    :parameters,
    :data
  ]

  @type t :: %__MODULE__{
          location: Local.t() | Remote.t(),
          parameters: [Payload.parameter()],
          data: Payload.job_data()
        }

  @spec new(Remote.t() | Local.t(), [Payload.parameter()], Payload.job_data()) :: t()
  def new(%Remote{} = location, parameters, data), do: build_spec(location, parameters, data)
  def new(%Local{} = location, parameters, data), do: build_spec(location, parameters, data)

  defp build_spec(location, parameters, data) when is_list(parameters) do
    %__MODULE__{
      location: location,
      parameters: parameters,
      data: data
    }
  end
end
