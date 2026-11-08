defmodule Exdock.Server.Logging.Status.TrackedJob do
  @moduledoc """
  Canonical lifecycle state retained while a status job is active.
  """

  alias Exdock.Server.Logging.Status.Lifecycle
  alias Exdock.Server.Jobs.Payload

  @enforce_keys [:locations, :data, :state]
  defstruct [:locations, :data, :state, message: nil]

  @type state :: {:ok, :requested} | {:error, term()}
  @type data :: Payload.job_data() | Payload.message()
  @type t :: %__MODULE__{
          locations: [Lifecycle.location()],
          data: data(),
          state: state(),
          message: Payload.message() | nil
        }

  @spec new([Lifecycle.location()], data(), state()) :: t()
  def new(locations, data, state) when is_list(locations) do
    %__MODULE__{locations: locations, data: data, state: state}
  end

  @spec put_message(t(), Payload.message()) :: t()
  def put_message(%__MODULE__{} = job, message), do: %{job | message: message}
end
