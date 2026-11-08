defmodule Exdock.Server.Connection.Handler.Lifecycle do
  @moduledoc """
  Pure lifecycle decisions for a server-side client connection.

  The handler GenServer owns sockets, timers, and logging. This module decides
  whether transport lifecycle events keep or stop the connection.
  """

  alias Exdock.Server.Connection.Session

  @type event ::
          :initialization_timeout
          | :socket_closed
          | {:socket_error, term()}
          | :heartbeat_timeout

  @type decision :: :continue | {:stop, term()}

  @spec decide(event(), Session.t()) :: decision()
  def decide(:initialization_timeout, %Session{} = session) do
    if Session.ready?(session), do: :continue, else: {:stop, :client_init_timeout}
  end

  def decide(:socket_closed, %Session{}), do: {:stop, :normal}
  def decide({:socket_error, reason}, %Session{}), do: {:stop, reason}
  def decide(:heartbeat_timeout, %Session{}), do: {:stop, :heartbeat_timeout}
end
