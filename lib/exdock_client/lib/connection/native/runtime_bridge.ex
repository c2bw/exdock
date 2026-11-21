defmodule Exdock.Client.Connection.Native.RuntimeBridge do
  @moduledoc "Stable runtime owner, scoped to exactly one NodeWire connection."
  use GenServer, restart: :temporary
  require Logger

  @resource_retry_ms 25
  @max_pending_resources 64
  @max_pending_resource_bytes 1_048_576
  alias Exdock.Client.Connection.{RuntimeInstaller, Metadata}
  def start_link(args), do: GenServer.start_link(__MODULE__, args)

  def init({conn, bundle, version}) do
    Process.monitor(conn.owner)

    {:ok, %{conn: conn, bundle: bundle, version: version, pending_resources: %{}, resource_retry_timer: nil},
     {:continue, :install}}
  end

  def handle_continue(:install, s) do
    result =
      RuntimeInstaller.install(s.bundle, s.conn.identity, Exdock.AgentRuntime, RuntimeInstaller)

    safe_result =
      case result do
        :ok -> :ok
        {:error, :runtime_busy} -> {:error, :runtime_busy}
        {:error, {:runtime_stop_failed, :runtime_busy}} -> {:error, :runtime_busy}
        _ -> {:error, :installation_failed}
      end

    ready = %{
      "bundle_version" => s.bundle["version"],
      "digest" => s.bundle["digest"],
      "metadata" => Metadata.collect(s.version)
    }

    message = {:runtime_installed, if(result == :ok, do: {:ok, ready}, else: safe_result)}

    case notify(s, message) do
      :ok -> {:noreply, s}
      {:error, :busy} -> recover_overload(s)
      {:error, _} -> {:stop, :normal, s}
    end
  end

  def handle_cast({:client_message, {:resource_sample, %{"container_id" => id} = payload}}, s) do
    if Map.has_key?(s.pending_resources, id),
      do: {:noreply, queue_resource(s, payload)},
      else: deliver({:resource_sample, payload}, s)
  end

  def handle_cast({:client_message, {kind, _} = message}, s) when kind in [:progress, :result],
    do: deliver(message, s)

  def handle_info({:timeout, timer, :retry_resources}, %{resource_retry_timer: timer} = s) do
    Enum.reduce_while(s.pending_resources, {:noreply, %{s | resource_retry_timer: nil}}, fn {id, payload}, {:noreply, s} ->
      s = %{s | pending_resources: Map.delete(s.pending_resources, id)}

      case deliver({:resource_sample, payload}, s) do
        {:noreply, %{resource_retry_timer: nil}} = result -> {:cont, result}
        result -> {:halt, result}
      end
    end)
  end

  def handle_info({:timeout, _, :retry_resources}, s), do: {:noreply, s}

  def handle_info({:DOWN, _, :process, owner, _}, %{conn: %{owner: owner}} = s),
    do: {:stop, :normal, s}

  defp deliver({kind, payload} = message, s) do
    case notify(s, {:runtime_message, message}) do
      :ok ->
        {:noreply, s}

      {:error, :busy} when kind == :resource_sample ->
        {:noreply, queue_resource(s, payload)}

      {:error, :busy} ->
        recover_overload(s)

      {:error, _} ->
        {:stop, :normal, s}
    end
  end

  defp notify(s, message) do
    case NodeWire.Connection.notify(s.conn, message) do
      {:error, {:outcome_unknown, _}} ->
        Logger.warning("Agent notification outcome is unknown; waiting for connection lifecycle")
        :ok

      result ->
        result
    end
  end

  defp queue_resource(s, %{"container_id" => id} = payload) do
    pending = Map.put(s.pending_resources, id, payload)

    if map_size(pending) <= @max_pending_resources and :erlang.external_size(pending) <= @max_pending_resource_bytes do
      timer = s.resource_retry_timer || :erlang.start_timer(@resource_retry_ms, self(), :retry_resources)
      %{s | pending_resources: pending, resource_retry_timer: timer}
    else
      Logger.debug("Dropping resource sample because the deferred sample queue is full")
      s
    end
  end

  defp recover_overload(s) do
    Logger.warning("Agent connection overloaded while publishing job state; closing it for recovery")
    NodeWire.Connection.close(s.conn, :normal)
    {:stop, :normal, s}
  end

  def terminate(_reason, s) do
    if s.resource_retry_timer, do: Process.cancel_timer(s.resource_retry_timer)
    :ok
  end

  def format_status(_), do: %{state: :redacted}
end
