defmodule Exdock.Client.Connection.Transport do
  @moduledoc "SSL transport boundary used by the persistent client connection."

  @callback connect(
              :inet.hostname() | :inet.ip_address(),
              :inet.port_number(),
              [:ssl.tls_client_option()],
              timeout()
            ) :: {:ok, :ssl.sslsocket()} | {:error, term()}
  @callback send(:ssl.sslsocket(), iodata()) :: :ok | {:error, term()}
  @callback activate(:ssl.sslsocket()) :: :ok | {:error, term()}
  @callback close(:ssl.sslsocket()) :: :ok | {:error, term()}

  @behaviour __MODULE__

  @impl true
  def connect(host, port, options, timeout), do: :ssl.connect(host, port, options, timeout)

  @impl true
  def send(socket, data), do: :ssl.send(socket, data)

  @impl true
  def activate(socket), do: :ssl.setopts(socket, active: :once)

  @impl true
  def close(socket), do: :ssl.close(socket)
end
