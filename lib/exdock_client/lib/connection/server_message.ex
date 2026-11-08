defmodule Exdock.Client.Connection.ServerMessage do
  @moduledoc """
  Pure routing for frames received from the Exdock server.

  The TCP client interprets these actions without mixing protocol policy into
  socket lifecycle code.
  """

  alias Exdock.Client.Connection.Protocol

  @spec route(binary()) ::
          {:server_error, term()}
          | {:runtime_bundle, map()}
          | {:execute, map()}
          | {:unknown, term()}
  def route(frame) when is_binary(frame) do
    frame
    |> Protocol.decode_message()
    |> route_decoded()
  end

  defp route_decoded({:error, :version_too_old}),
    do: {:server_error, {:version_mismatch, :version_too_old}}

  defp route_decoded({:error, :version_too_new}),
    do: {:server_error, {:version_mismatch, :version_too_new}}

  defp route_decoded({:error, :invalid_auth}),
    do: {:server_error, {:authentication_error, :invalid_auth}}

  defp route_decoded({:error, :duplicate_name}),
    do: {:server_error, {:authentication_error, :duplicate_name}}

  defp route_decoded({:error, :invalid_name}),
    do: {:server_error, {:authentication_error, :invalid_name}}

  defp route_decoded({:error, reason}), do: {:server_error, reason}
  defp route_decoded({:runtime_bundle, bundle}), do: {:runtime_bundle, bundle}
  defp route_decoded({:command, command}), do: {:execute, command}
  defp route_decoded(message), do: {:unknown, message}
end
