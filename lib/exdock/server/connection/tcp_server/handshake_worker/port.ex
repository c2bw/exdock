defmodule Exdock.Server.Connection.TCPServer.HandshakeWorker.Port do
  @moduledoc """
  Boundary for TLS socket ownership and connection-handler lifecycle calls.

  A context argument keeps implementations stateless while allowing focused
  tests to carry scenario data without replacing individual callbacks.
  """

  @callback close(context :: term(), socket :: term()) :: term()
  @callback controlling_process(context :: term(), socket :: term(), pid()) ::
              :ok | {:error, term()}
  @callback handshake(context :: term(), socket :: term(), timeout()) ::
              {:ok, term()} | {:error, term()}
  @callback setopts(context :: term(), socket :: term(), keyword()) ::
              :ok | {:error, term()}
  @callback start_handler(
              context :: term(),
              GenServer.server(),
              String.t(),
              socket :: term(),
              GenServer.server()
            ) :: {:ok, pid()} | {:error, term()}
  @callback stop_handler(context :: term(), pid(), reason :: term()) :: term()
  @callback activate_handler(context :: term(), pid(), pos_integer()) :: :ok | {:error, term()}
end
