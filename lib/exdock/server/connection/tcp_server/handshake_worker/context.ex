defmodule Exdock.Server.Connection.TCPServer.HandshakeWorker.Context do
  @moduledoc "Typed dependencies and limits for one accepted socket handshake."

  alias Exdock.Server.Connection.TCPServer
  alias Exdock.Server.Connection.TCPServer.HandshakeWorker.Port.SSL

  @default_handshake_timeout 5_000
  @default_socket_handoff_timeout 1_000

  @enforce_keys [:server, :handler_supervisor, :auth_key, :port]
  defstruct [
    :server,
    :handler_supervisor,
    :auth_key,
    :port,
    :port_context,
    :max_frame_size,
    task_supervisor: TCPServer.TaskSupervisor,
    handshake_timeout: @default_handshake_timeout,
    socket_handoff_timeout: @default_socket_handoff_timeout
  ]

  @type t :: %__MODULE__{
          server: GenServer.server(),
          handler_supervisor: GenServer.server(),
          auth_key: String.t(),
          port: module(),
          port_context: term(),
          max_frame_size: pos_integer(),
          task_supervisor: Supervisor.supervisor(),
          handshake_timeout: timeout(),
          socket_handoff_timeout: timeout()
        }

  @spec new(GenServer.server(), GenServer.server(), String.t(), keyword()) ::
          {:ok, t()} | {:error, term()}
  def new(server, handler_supervisor, auth_key, opts)
      when is_binary(auth_key) and is_list(opts) do
    with {:ok, max_frame_size} <- required_positive_integer(opts, :max_frame_size),
         {:ok, handshake_timeout} <- timeout(opts, :handshake_timeout, @default_handshake_timeout),
         {:ok, socket_handoff_timeout} <-
           timeout(opts, :socket_handoff_timeout, @default_socket_handoff_timeout),
         {:ok, port} <- module_option(opts, :port, SSL) do
      {:ok,
       %__MODULE__{
         server: server,
         handler_supervisor: handler_supervisor,
         auth_key: auth_key,
         port: port,
         port_context: Keyword.get(opts, :port_context),
         max_frame_size: max_frame_size,
         task_supervisor: Keyword.get(opts, :task_supervisor, TCPServer.TaskSupervisor),
         handshake_timeout: handshake_timeout,
         socket_handoff_timeout: socket_handoff_timeout
       }}
    end
  end

  defp required_positive_integer(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when is_integer(value) and value > 0 -> {:ok, value}
      {:ok, value} -> {:error, {:invalid_option, key, value}}
      :error -> {:error, {:missing_option, key}}
    end
  end

  defp timeout(opts, key, default) do
    case Keyword.get(opts, key, default) do
      value when value == :infinity or (is_integer(value) and value >= 0) -> {:ok, value}
      value -> {:error, {:invalid_option, key, value}}
    end
  end

  defp module_option(opts, key, default) do
    case Keyword.get(opts, key, default) do
      value when is_atom(value) -> {:ok, value}
      value -> {:error, {:invalid_option, key, value}}
    end
  end
end
