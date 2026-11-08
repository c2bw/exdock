defmodule Exdock.Server.Logging.Context do
  @moduledoc """
  Runtime values supplied to deterministic logging state transitions.

  The logging process owns clocks and identifier generation. Reducers consume
  their values without reaching into wall-clock or UUID services directly.
  """

  @enforce_keys [:now, :id]
  defstruct [:now, :id]

  @type t :: %__MODULE__{
          now: DateTime.t(),
          id: String.t()
        }

  @spec new(DateTime.t(), String.t()) :: t()
  def new(%DateTime{} = now, id) when is_binary(id), do: %__MODULE__{now: now, id: id}

  @spec runtime() :: t()
  def runtime, do: new(DateTime.utc_now(:millisecond), Ecto.UUID.generate())
end
