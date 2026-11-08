defmodule Exdock.Server.Connection.Handler.Bootstrap do
  @moduledoc """
  Coordinates authentication, registration, and runtime-bundle negotiation.

  The connection handler remains the socket owner and interprets these results
  by writing protocol frames, starting timers, and notifying the TCP server.
  """

  alias Exdock.Server.Connection.Handshake
  alias Exdock.Server.Connection.Handler.State
  alias Exdock.NodeId
  alias Exdock.Server.Connection.RuntimeBundleProvider
  alias Exdock.Server.Connection.Session
  alias Exdock.Server.Connection.TCPServer.ClientRegistry

  @type authenticate_result ::
          {:ok, State.t(), map()}
          | {:error,
             :invalid_auth
             | :duplicate_name
             | :invalid_name
             | :load_module_fail
             | {:version_requirement, String.t()}, State.t()}

  @spec authenticate(State.t(), term(), term(), String.t(), keyword()) :: authenticate_result()
  def authenticate(%State{} = state, client_version, presented_auth, client_name, opts \\ [])
      when is_binary(client_name) and is_list(opts) do
    state = State.put_session(state, Session.identify(state.session, client_name))
    register = Keyword.get(opts, :register, &register_client/2)
    build_bundle = Keyword.get(opts, :build_bundle, &RuntimeBundleProvider.build/0)

    with :ok <- Handshake.validate_client(client_version, state.auth_key, presented_auth),
         :ok <- register.(client_name, self()) do
      state = authenticate_session(state)

      case build_bundle.() do
        {:ok, bundle} ->
          session = Session.offer_bundle(state.session, bundle["digest"])
          {:ok, State.put_session(state, session), bundle}

        {:error, :load_module_fail} ->
          {:error, :load_module_fail, state}
      end
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  @spec initialize(State.t(), term(), term()) ::
          {:ok, State.t()} | {:error, :runtime_bundle_mismatch, State.t()}
  def initialize(%State{} = state, bundle_version, digest) do
    if Handshake.ready?(
         RuntimeBundleProvider.version(),
         state.session.bundle_digest,
         bundle_version,
         digest
       ) do
      {:ok, State.put_session(state, Session.initialize(state.session))}
    else
      {:error, :runtime_bundle_mismatch, state}
    end
  end

  defp authenticate_session(%State{} = state) do
    :ok = NodeId.validate(state.session.client_name)
    State.put_session(state, Session.authenticate(state.session))
  end

  defp register_client(client_name, handler) do
    case ClientRegistry.register(client_name, handler) do
      :ok -> :ok
      {:error, :duplicate} -> {:error, :duplicate_name}
      {:error, :invalid} -> {:error, :invalid_name}
    end
  end
end
