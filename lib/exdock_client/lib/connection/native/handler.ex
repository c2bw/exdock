defmodule Exdock.Client.Connection.Native.Handler do
  @moduledoc "Adapts existing command validation and runtime installation to NodeWire."
  use NodeWire.Handler
  require Logger
  alias Exdock.Client.Connection.{RuntimeInstaller, Native.RuntimeBridge}
  alias Exdock.Protocol.{Command, Compatibility, Message, RuntimeBundle}

  def init(config) do
    RuntimeInstaller.prepare()
    {:ok, %{config: config, bridge: nil}}
  end

  def handshake_data(_, s),
    do:
      {:ok,
       %{
         "node" => s.config.node,
         "agent_version" => Compatibility.agent_version(),
         "auth_token" => s.config.token
       }, s}

  def validate_message(:runtime_bundle, bundle, _, _) do
    case RuntimeBundle.validate(bundle, &RuntimeInstaller.allowed_module?/1) do
      :ok -> {:ok, bundle}
      _ -> {:error, :invalid_bundle}
    end
  end

  def validate_message(:command, command, _, _) do
    case Command.decode(command) do
      {:ok, _validated} -> {:ok, command}
      _ -> {:error, :invalid_command}
    end
  end

  def handle_message({:runtime_bundle, bundle}, conn, s) do
    case DynamicSupervisor.start_child(
           Exdock.Client.Connection.RuntimeBridges,
           {RuntimeBridge, {conn, bundle, Compatibility.agent_version()}}
         ) do
      {:ok, bridge} -> {:noreply, %{s | bridge: bridge}}
      _ -> {:stop, :bridge_failed, s}
    end
  end

  def handle_message({:command, command}, _, s) do
    Task.Supervisor.start_child(Exdock.Client.Connection.TaskSupervisor, fn ->
      apply(
        Map.get(s.config, :runtime_executor, Exdock.Client.Connection.RuntimeExecutor),
        :execute,
        [command]
      )
    end)

    {:noreply, s}
  end

  def handle_info({:runtime_installed, {:ok, ready}}, _, s),
    do: {:noreply, s, [{:send, {:ready, ready}}, {:phase, :ready}]}

  def handle_info({:runtime_installed, {:error, :runtime_busy}}, _, s) do
    Logger.info("Runtime upgrade deferred: runtime_busy")
    {:stop, :runtime_busy, s}
  end

  def handle_info({:runtime_installed, {:error, _}}, _, s), do: {:stop, :installation_failed, s}
  def handle_info({:runtime_message, message}, _, s), do: {:noreply, s, [{:send, message}]}

  def validate_outgoing(
        :ready,
        %{"bundle_version" => v, "digest" => d, "metadata" => m} = p,
        _,
        _
      )
      when is_binary(v) and is_binary(d) and is_map(m), do: {:ok, p}

  def validate_outgoing(:progress, p, _, _), do: valid(Message.valid_progress?(p), p)
  def validate_outgoing(:result, p, _, _), do: valid(Message.valid_result?(p), p)

  def validate_outgoing(:resource_sample, p, _, _),
    do: valid(Message.valid_resource_sample?(p), p)

  def validate_outgoing(_, _, _, _), do: {:error, :invalid_outgoing}
  defp valid(true, p), do: {:ok, p}
  defp valid(_, _), do: {:error, :invalid_payload}
end
