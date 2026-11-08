defmodule Exdock.Server.Connection.TCPServer.Listener do
  @moduledoc """
  Owns the TLS listener socket and accepts connections for the TCP server.

  Each accepted socket is handed to a bounded handshake worker. A listener
  error terminates this process so its supervisor can close the stale socket
  and restart the complete accept lifecycle.
  """

  use GenServer

  require Logger

  alias Exdock.Server.Connection.SelfCert
  alias Exdock.Server.Connection.TCPServer.HandshakeWorker
  alias Exdock.Server.Connection.Utils

  defstruct [:server, :handler_supervisor, :auth_key, :socket, handshake_opts: []]

  @type t :: %__MODULE__{
          server: GenServer.server(),
          handler_supervisor: GenServer.server(),
          auth_key: String.t(),
          socket: :ssl.sslsocket(),
          handshake_opts: keyword()
        }

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init({server, handler_supervisor, auth_key, port})
      when is_binary(auth_key) and is_integer(port) and port >= 0 do
    init({server, handler_supervisor, auth_key, port, []})
  end

  def init({server, handler_supervisor, auth_key, port, handshake_opts})
      when is_binary(auth_key) and is_integer(port) and port >= 0 do
    case listen(port) do
      {:ok, socket} ->
        Logger.info("Listening for connections on port #{port}")

        {:ok,
         %__MODULE__{
           server: server,
           handler_supervisor: handler_supervisor,
           auth_key: auth_key,
           socket: socket,
           handshake_opts: handshake_opts
         }, {:continue, :accept}}

      {:error, reason} ->
        Logger.error("Failed to listen for TCP connections on port #{port}: #{inspect(reason)}")
        {:stop, {:listen_failed, reason}}
    end
  end

  @impl true
  def handle_continue(:accept, %__MODULE__{} = state) do
    case accept_client(state) do
      :ok ->
        {:noreply, state, {:continue, :accept}}

      {:error, reason} ->
        Logger.error("TCP listener stopped accepting connections: #{inspect(reason)}")
        {:stop, {:accept_failed, reason}, state}
    end
  end

  @impl true
  def terminate(_reason, %__MODULE__{socket: socket}) do
    :ssl.close(socket)
    :ok
  end

  defp accept_client(%__MODULE__{
         server: server,
         handler_supervisor: handler_supervisor,
         auth_key: auth_key,
         socket: listener_socket,
         handshake_opts: handshake_opts
       }) do
    case :ssl.transport_accept(listener_socket) do
      {:ok, ssl_socket} ->
        Logger.debug("Accepted new TCP connection from client: #{inspect(Utils.client_info(ssl_socket))}")
        HandshakeWorker.start(ssl_socket, server, handler_supervisor, auth_key, handshake_opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec listen(non_neg_integer()) :: {:ok, :ssl.sslsocket()} | {:error, :ssl.reason()}
  defp listen(port) do
    {certificate, key_der} = SelfCert.generate()

    :ssl.listen(port,
      verify: :verify_none,
      secure_renegotiate: true,
      key: key_der,
      cert: certificate
    )
  end
end
