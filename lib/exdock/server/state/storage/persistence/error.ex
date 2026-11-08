defmodule Exdock.Server.State.Storage.Persistence.Error do
  @moduledoc """
  Structured failure returned by persistence operations.

  Storage code keeps the operation and original cause intact. Human-readable
  formatting is reserved for logging and presentation boundaries.
  """

  @enforce_keys [:operation, :cause]
  defstruct [:operation, :cause]

  @type t :: %__MODULE__{operation: atom(), cause: term()}

  @spec new(atom(), term()) :: t()
  def new(operation, cause) when is_atom(operation),
    do: %__MODULE__{operation: operation, cause: cause}

  @doc "Formats a persistence failure for a human-readable boundary."
  @spec format(t()) :: String.t()
  def format(%__MODULE__{operation: operation, cause: cause}),
    do: "db_error: #{operation}: #{inspect(cause)}"
end
