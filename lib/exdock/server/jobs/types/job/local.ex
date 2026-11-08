defmodule Exdock.Server.Jobs.Job.Local do
  @moduledoc """
  Runtime function for a server-local job.
  """

  alias Exdock.Server.Jobs.Runtime

  defstruct [:function]
  @type runner :: (String.t() -> term()) | (String.t(), Runtime.t() -> term())
  @type t :: %__MODULE__{function: runner()}

  @spec new(runner()) :: t()
  def new(f) when is_function(f) do
    %__MODULE__{
      function: f
    }
  end
end
