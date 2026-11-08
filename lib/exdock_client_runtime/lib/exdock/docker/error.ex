defmodule Exdock.Docker.Error do
  @moduledoc """
  Structured failure returned by the Docker Engine boundary.

  Keeping the operation, original cause, HTTP status, and retry hint together
  lets orchestration make decisions without parsing an operator-facing string.
  The error is rendered only when it is logged or encoded for the wire.
  """

  alias DockerEngineAPI.Model
  alias Exdock.Docker.Local.GeneratedResponse

  @type operation :: atom() | {atom(), term()}

  @enforce_keys [:operation, :cause, :message, :retryable?]
  defstruct [:operation, :status, :cause, :message, retryable?: false]

  @type t :: %__MODULE__{
          operation: operation(),
          status: non_neg_integer() | nil,
          cause: term(),
          message: String.t(),
          retryable?: boolean()
        }

  @spec new(operation(), term(), keyword()) :: t()
  def new(operation, cause, opts \\ []) when is_list(opts) do
    status = Keyword.get(opts, :status, status(cause))

    %__MODULE__{
      operation: operation,
      status: status,
      cause: cause,
      message: Keyword.get_lazy(opts, :message, fn -> message(cause, status) end),
      retryable?: Keyword.get(opts, :retryable?, retryable?(cause, status))
    }
  end

  @spec message(t()) :: String.t()
  def message(%__MODULE__{message: message}), do: message

  @doc "Converts a Docker error to its protocol-safe representation."
  @spec to_wire(term()) :: term()
  def to_wire(%__MODULE__{} = error), do: message(error)
  def to_wire(error), do: error

  defp status(cause), do: GeneratedResponse.status(cause)

  defp message(%Model.ErrorResponse{message: message}, _status) when is_binary(message), do: message

  defp message(cause, status) do
    GeneratedResponse.message(cause) || fallback_message(cause, status)
  end

  defp fallback_message(message, _status) when is_binary(message), do: message
  defp fallback_message(reason, _status) when is_atom(reason), do: Atom.to_string(reason)
  defp fallback_message(%{__exception__: true} = exception, _status), do: Exception.message(exception)
  defp fallback_message(_cause, _status), do: "Unhandled Docker error"

  defp retryable?(_cause, status) when status in [408, 425, 429], do: true
  defp retryable?(_cause, status) when is_integer(status) and status >= 500, do: true

  defp retryable?(cause, _status)
       when cause in [:closed, :econnrefused, :econnreset, :enetdown, :enetunreach, :timeout],
       do: true

  defp retryable?(_cause, _status), do: false
end
