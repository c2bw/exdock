defmodule ExdockClient.Application do
  @moduledoc """
  OTP application entrypoint for the standalone Exdock client node.

  The client release reads connection settings from the environment and starts a
  single TCP client process. The server later ships the modules required for
  remote job execution after authentication succeeds.
  """

  use Application
  require Logger

  @doc """
  Start the client supervision tree from release/runtime configuration.
  """
  def start(_type, _args) do
    package_version = Application.spec(:exdock_client, :vsn) |> to_string()
    protocol_version = Exdock.Wire.V1.version()

    Logger.info("Starting Exdock client package_version=#{package_version} protocol_version=#{protocol_version}")

    # Get ENV variables
    fetch_env = fn var ->
      case Application.fetch_env(:exdock_client, var) do
        {:ok, val} ->
          val

        :error ->
          Logger.error("Error fetching environment variable: #{var}")
          exit({:error, :env_fetch_error})
      end
    end

    node_name = fetch_env.(:node_name)
    server_host = fetch_env.(:server_host) |> String.to_charlist()
    server_port = fetch_env.(:server_port)
    auth_key = fetch_env.(:auth_key)

    children = [
      {Registry, keys: :unique, name: Exdock.AgentRegistry},
      {Task.Supervisor, name: Exdock.Client.Connection.TaskSupervisor},
      Exdock.Client.Connection.RuntimeInstaller,
      {DynamicSupervisor, strategy: :one_for_one, name: Exdock.Client.Connection.RuntimeBridges},
      {NodeWire.Client,
       name: Exdock.AgentConnection,
       protocols: [Exdock.Wire.V1],
       handler: Exdock.Client.Connection.Native.Handler,
       handler_args: %{node: node_name, token: :crypto.hash(:sha256, auth_key) |> Base.encode16()},
       transport:
         {:tls,
          [
            host: server_host,
            port: server_port,
            options: Application.fetch_env!(:exdock_client, :agent_tls_options)
          ]},
       phases: Exdock.Wire.Phases.client(),
       reconnect_policy: %{runtime_busy: :transient},
       handshake: [required_capabilities: ["jobs.v1"]],
       readiness_timeout_ms: 35_000}
    ]

    opts = [strategy: :one_for_one, name: ExdockClient.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
