defmodule ExdockWeb.PageLive.Utils.LiveOperation do
  @moduledoc false

  require Logger

  @spec handle(Phoenix.LiveView.Socket.t(), Exdock.Operations.result()) :: Phoenix.LiveView.Socket.t()
  def handle(socket, {:ok, _operation_id}), do: socket

  def handle(socket, {:error, reason}) do
    log_rejection(reason)
    Phoenix.LiveView.put_flash(socket, :error, "Operation could not be accepted")
  end

  @spec handle_component(Phoenix.LiveView.Socket.t(), Exdock.Operations.result()) :: Phoenix.LiveView.Socket.t()
  def handle_component(socket, {:ok, _operation_id}), do: socket

  def handle_component(socket, {:error, reason}) do
    log_rejection(reason)
    component_flash(:error, "Operation could not be accepted")
    socket
  end

  @spec invalid(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def invalid(socket, message \\ "Invalid request") when is_binary(message) do
    Phoenix.LiveView.put_flash(socket, :error, message)
  end

  @spec invalid_component(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def invalid_component(socket, message \\ "Invalid request") when is_binary(message) do
    component_flash(:error, message)
    socket
  end

  defp component_flash(kind, message), do: send(self(), {:update_flash, {kind, message}})
  defp log_rejection(reason), do: Logger.warning("Operation rejected: #{inspect(reason)}")
end
