defmodule Exdock.Protocol.Messages.JobResult do
  @moduledoc "Validated client result paired with its dispatched server job."

  defstruct [:job, :result]

  @type t :: %__MODULE__{job: map(), result: map()}

  @spec new(map(), map()) :: t()
  def new(job, result) when is_map(job) and is_map(result),
    do: %__MODULE__{job: job, result: result}
end
