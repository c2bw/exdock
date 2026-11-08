defmodule Exdock.Status.Dashboard.Row do
  @moduledoc """
  Public operator-facing state for one status dashboard entry.
  """

  @enforce_keys [:state, :data]
  defstruct [:state, :data, message: nil]

  @type state :: {:ok, :requested} | {:error, term()} | {:warning, String.t()}
  @type t :: %__MODULE__{
          state: state(),
          data: term(),
          message: term() | nil
        }

  @spec new(state(), term()) :: t()
  def new(state, data), do: %__MODULE__{state: state, data: data}

  @spec put_data(t(), term()) :: t()
  def put_data(%__MODULE__{} = row, data), do: %{row | data: data}

  @spec put_message(t(), term()) :: t()
  def put_message(%__MODULE__{} = row, message), do: %{row | message: message}

  @spec error?(t()) :: boolean()
  def error?(%__MODULE__{state: {:error, _error}}), do: true
  def error?(%__MODULE__{}), do: false

  @spec attention?(t()) :: boolean()
  def attention?(%__MODULE__{state: {:warning, _warning}}), do: true
  def attention?(%__MODULE__{} = row), do: error?(row)
end
