defmodule Exdock.Docker.Local.GeneratedResponse do
  @moduledoc """
  Adapter-specific access to responses emitted by the generated Docker client.

  Tesla is intentionally contained here and in the streamed pull transport.
  """

  alias DockerEngineAPI.Model

  @spec status(term()) :: non_neg_integer() | nil
  def status(%Tesla.Env{status: status}) when is_integer(status), do: status
  def status(_response), do: nil

  @spec message(term()) :: String.t() | nil
  def message(%Tesla.Env{body: %Model.ErrorResponse{message: message}}) when is_binary(message), do: message
  def message(%Tesla.Env{status: status}) when is_integer(status), do: "HTTP Error: #{status}"
  def message(_response), do: nil
end
