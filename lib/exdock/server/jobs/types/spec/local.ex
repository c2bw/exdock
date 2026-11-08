defmodule Exdock.Server.Jobs.Spec.Local do
  @moduledoc """
  Local jobs are executed in a server-side task.
  """

  alias Exdock.Server.Jobs.Runtime

  defstruct [:function]
  @type runner :: (String.t() -> term()) | (String.t(), Runtime.t() -> term())
  @type t :: %__MODULE__{function: runner()}

  @spec new(runner()) :: t()
  def new(function) when is_function(function), do: %__MODULE__{function: function}
end
