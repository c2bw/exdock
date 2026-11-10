defmodule Exdock.Server.Connection.TCPServer.HandshakeWorker do
  @moduledoc """
  Owns TLS handshake and transfer of one accepted socket to its handler.

  The listener remains responsible only for accepting sockets. Transport and
  handler callbacks are injectable so ownership and failure paths can be tested
  without opening real sockets.
  """

  require Logger

  alias Exdock.Server.Connection.TCPServer.HandshakeWorker.Context

  @spec start(term(), GenServer.server(), GenServer.server(), String.t(), keyword()) ::
          :ok | {:error, term()}
  def start(socket, server, handler_supervisor, auth_key, opts \\ [])
      when is_binary(auth_key) and is_list(opts) do
    case Context.new(server, handler_supervisor, auth_key, opts) do
      {:ok, context} ->
        start_worker(socket, context)

      {:error, reason} ->
        close_with_options(socket, opts)
        {:error, {:invalid_handshake_context, reason}}
    end
  end

  @doc false
  @spec await_handoff(GenServer.server(), GenServer.server(), String.t(), keyword()) ::
          :ok | {:error, term()}
  def await_handoff(server, handler_supervisor, auth_key, opts \\ []) do
    with {:ok, context} <- Context.new(server, handler_supervisor, auth_key, opts) do
      await_handoff(context)
    end
  end

  defp start_worker(socket, %Context{} = context) do
    case Task.Supervisor.start_child(context.task_supervisor, fn -> await_handoff(context) end) do
      {:ok, worker_pid} ->
        handoff_to_worker(socket, worker_pid, context)

      {:error, reason} ->
        context.port.close(context.port_context, socket)
        {:error, {:handshake_worker_start_failed, reason}}
    end
  end

  defp close_with_options(socket, opts) do
    port = Keyword.get(opts, :port, Exdock.Server.Connection.TCPServer.HandshakeWorker.Port.SSL)
    context = Keyword.get(opts, :port_context)
    if is_atom(port), do: port.close(context, socket), else: :ok
  end

  defp await_handoff(%Context{} = context) do
    receive do
      {:continue_handshake, socket} ->
        connect_client(socket, context)
    after
      context.socket_handoff_timeout -> {:error, :socket_handoff_timeout}
    end
  end

  defp handoff_to_worker(socket, worker_pid, %Context{} = context) do
    case context.port.controlling_process(context.port_context, socket, worker_pid) do
      :ok ->
        send(worker_pid, {:continue_handshake, socket})
        :ok

      {:error, reason} ->
        Task.Supervisor.terminate_child(context.task_supervisor, worker_pid)
        context.port.close(context.port_context, socket)
        {:error, {:handshake_socket_handoff_failed, reason}}
    end
  end

  defp connect_client(socket, %Context{} = context) do
    case context.port.handshake(context.port_context, socket, context.handshake_timeout) do
      {:ok, client_socket} ->
        start_handler(client_socket, context)

      {:error, reason} ->
        Logger.error("SSL handshake failed: #{inspect(reason)}")
        context.port.close(context.port_context, socket)
        {:error, {:handshake_failed, reason}}
    end
  end

  defp start_handler(client_socket, %Context{} = context) do
    case context.port.start_handler(
           context.port_context,
           context.server,
           context.auth_key,
           client_socket,
           context.handler_supervisor
         ) do
      {:ok, handler_pid} ->
        handoff_to_handler(client_socket, handler_pid, context)

      {:error, reason} ->
        Logger.error("Failed to start connection handler: #{inspect(reason)}")
        context.port.close(context.port_context, client_socket)
        {:error, {:handler_start_failed, reason}}
    end
  end

  defp handoff_to_handler(client_socket, handler_pid, %Context{} = context) do
    with :ok <- set_client_socket_options(client_socket, handler_pid, context),
         :ok <- transfer_client_socket(client_socket, handler_pid, context),
         :ok <- context.port.activate_handler(context.port_context, handler_pid, context.max_frame_size) do
      :ok
    end
  end

  defp set_client_socket_options(client_socket, handler_pid, %Context{} = context) do
    case context.port.setopts(context.port_context, client_socket, tcp_options()) do
      :ok ->
        Logger.debug("Successfully set TCP options")
        :ok

      {:error, reason} ->
        Logger.debug("Failed to set SSL options for client socket: #{inspect(reason)}")
        context.port.stop_handler(context.port_context, handler_pid, :set_ssl_opts_fail)
        {:error, {:set_ssl_opts_failed, reason}}
    end
  end

  defp transfer_client_socket(client_socket, handler_pid, %Context{} = context) do
    case context.port.controlling_process(context.port_context, client_socket, handler_pid) do
      :ok ->
        Logger.debug("Successfully set controlling process")
        :ok

      {:error, reason} ->
        Logger.debug("Failed to set controlling process for client socket: #{inspect(reason)}")
        context.port.stop_handler(context.port_context, handler_pid, :set_control_fail)
        {:error, {:set_control_failed, reason}}
    end
  end

  defp tcp_options() do
    [
      :binary,
      packet: :raw,
      active: false,
      send_timeout: 5_000,
      send_timeout_close: true,
      reuseaddr: false
    ]
  end
end
