defmodule Exdock.Client.Connection.Native.RuntimeBridge do
  @moduledoc "Stable runtime owner, scoped to exactly one NodeWire connection."
  use GenServer, restart: :temporary
  alias Exdock.Client.Connection.{RuntimeInstaller, Metadata}
  def start_link(args), do: GenServer.start_link(__MODULE__, args)

  def init({conn, bundle, version}) do
    Process.monitor(conn.owner)
    {:ok, %{conn: conn, bundle: bundle, version: version}, {:continue, :install}}
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

    NodeWire.Connection.notify(
      s.conn,
      {:runtime_installed, if(result == :ok, do: {:ok, ready}, else: safe_result)}
    )

    {:noreply, s}
  end

  def handle_cast({:client_message, {kind, payload}}, s)
      when kind in [:progress, :result, :resource_sample] do
    case NodeWire.Connection.notify(s.conn, {:runtime_message, {kind, payload}}) do
      :ok -> {:noreply, s}
      _ -> {:stop, :normal, s}
    end
  end

  def handle_info({:DOWN, _, :process, owner, _}, %{conn: %{owner: owner}} = s),
    do: {:stop, :normal, s}

  def format_status(_), do: %{state: :redacted}
end
