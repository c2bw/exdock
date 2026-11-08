defmodule Exdock.Client.Connection.Lifecycle do
  @moduledoc """
  Pure decisions for client connection events.

  `TCPClient` interprets these decisions by performing socket I/O, scheduling
  timers, installing runtime bundles, or updating its state.
  """

  alias Exdock.Client.Connection.Session

  @type decision ::
          :ignore
          | :connect
          | :send_heartbeat
          | :authenticate
          | :handle_frame
          | :initialize_runtime
          | {:disconnect, String.t(), boolean()}

  @spec decide(term(), Session.t(), String.t()) :: decision()
  def decide({:reconnect_timeout, true}, %Session{} = session, _client_version) do
    if Session.connectable?(session), do: :connect, else: :ignore
  end

  def decide({:reconnect_timeout, false}, %Session{}, _client_version), do: :ignore

  def decide(:heartbeat, %Session{} = session, _client_version) do
    if Session.socket_open?(session), do: :send_heartbeat, else: :ignore
  end

  def decide(:authenticate, %Session{} = session, _client_version) do
    if Session.in_phase?(session, :authenticating), do: :authenticate, else: :ignore
  end

  def decide({:runtime_bundle, current_socket?}, %Session{} = session, _client_version) do
    if current_socket? and Session.in_phase?(session, :authenticating),
      do: :initialize_runtime,
      else: :ignore
  end

  def decide({:socket_frame, true}, %Session{}, _client_version), do: :handle_frame
  def decide({:socket_frame, false}, %Session{}, _client_version), do: :ignore
  def decide({:socket_closed, true}, %Session{}, _client_version), do: {:disconnect, "SSL connection closed", true}
  def decide({:socket_closed, false}, %Session{}, _client_version), do: :ignore

  def decide({:socket_error, true, reason}, %Session{}, _client_version),
    do: {:disconnect, "TCP error: #{reason}", true}

  def decide({:socket_error, false, _reason}, %Session{}, _client_version), do: :ignore

  def decide({:server_error, {:version_mismatch, version_error}}, %Session{}, _client_version),
    do: {:disconnect, "version_mismatch: #{inspect(version_error)}", false}

  def decide({:server_error, {:version_requirement, requirement}}, %Session{}, client_version),
    do: {:disconnect, "client_version [#{client_version}] want #{inspect(requirement)}", false}

  def decide({:server_error, {:authentication_error, auth_error}}, %Session{}, _client_version),
    do: {:disconnect, "auth_error: #{inspect(auth_error)}", false}

  def decide({:server_error, error}, %Session{}, _client_version),
    do: {:disconnect, "server returned an error: #{inspect(error)}", true}
end
