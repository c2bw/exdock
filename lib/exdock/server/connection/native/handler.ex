defmodule Exdock.Server.Connection.Native.Handler do
  @moduledoc "Native transport adapter retaining Exdock validation, job tracking and mappings."
  use NodeWire.Handler
  alias Exdock.Server.Connection.{Handshake, Protocol, RuntimeBundleProvider, Session}
  alias Exdock.Server.Connection.Handler.State
  alias Exdock.Server.Connection.Handler.SessionEffects
  alias Exdock.Protocol.{AgentMetadata, Message}

  def init(config),
    do:
      {:ok,
       %{
         domain: State.new(config.observer, config.token, nil),
         observer: config.observer,
         bundle: nil
       }}

  def authenticate(%{"node" => node, "agent_version" => version, "auth_token" => token}, _, s) do
    with :ok <- Exdock.NodeId.validate(node),
         :ok <- Handshake.validate_client(version, s.domain.auth_key, token) do
      domain = %{s.domain | session: Session.identify(s.domain.session, node)}
      {:ok, node, %{s | domain: domain}}
    else
      _ -> {:error, :authentication_failed, s}
    end
  end

  def authenticate(_, _, s), do: {:error, :authentication_failed, s}

  def handle_negotiated(_, s) do
    case RuntimeBundleProvider.build() do
      {:ok, bundle} -> {:noreply, %{s | bundle: bundle}, [{:send, {:runtime_bundle, bundle}}]}
      _ -> {:stop, :bundle_failed, s}
    end
  end

  def validate_message(
        :ready,
        %{"bundle_version" => v, "digest" => d, "metadata" => metadata},
        _,
        s
      ) do
    with true <- Handshake.ready?(s.bundle["version"], s.bundle["digest"], v, d),
         {:ok, metadata} <- AgentMetadata.sanitize(metadata) do
      {:ok, metadata}
    else
      _ -> {:error, :invalid_ready}
    end
  end

  def validate_message(name, payload, _, _) when name in [:progress, :result, :resource_sample],
    do: Protocol.validate_payload(name, payload)

  def handle_message({:ready, metadata}, conn, s) do
    send(s.observer, {:native_metadata, conn.id, metadata})
    {:noreply, s, [{:phase, :ready}]}
  end

  def handle_message({name, message}, _, s) do
    action = if name == :result, do: {:job_result, message}, else: {:client_message, message}
    {:noreply, domain} = SessionEffects.interpret(action, s.domain, nil, <<>>)
    {:noreply, %{s | domain: domain}}
  end

  def validate_outgoing(:command, p, _, _),
    do: if(Message.valid_command?(p), do: {:ok, p}, else: {:error, :invalid_command})

  def validate_outgoing(:runtime_bundle, p, _, _), do: {:ok, p}

  def handle_sent({:track_job, job}, _, s),
    do: {:noreply, %{s | domain: State.track_dispatched_job(s.domain, job)}}

  def handle_info({:remote_job_timeout, id, token}, _, s) do
    case State.expire_dispatched_job(s.domain, id, token) do
      {:ok, domain, message} ->
        SessionEffects.forward_client_message(domain, message)
        {:noreply, %{s | domain: domain}}

      _ ->
        {:noreply, s}
    end
  end
end
