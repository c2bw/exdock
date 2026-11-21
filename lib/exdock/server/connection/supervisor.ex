defmodule Exdock.Server.Connection.Supervisor do
  @moduledoc "Supervises the native NodeWire transport and Exdock domain boundary."
  use Supervisor
  alias Exdock.Server.Connection.{SelfCert, TCPServer}
  def start_link(args), do: Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  def init({key, port}), do: init({key, port, []})

  def init({key, port, opts}) do
    tls =
      Keyword.get_lazy(opts, :tls_options, fn -> Application.get_env(:exdock, :agent_tls_options) || generated_tls_options() end)

    children = [
      {TCPServer, name: TCPServer, registry: {:nodewire, Exdock.AgentServer}, reset_connections: true},
      {NodeWire.Server,
       name: Exdock.AgentServer,
       protocols: [Exdock.Wire.V1],
       handler: Exdock.Server.Connection.Native.Handler,
       handler_args: %{token: :crypto.hash(:sha256, key) |> Base.encode16(), observer: TCPServer},
       transport: {:tls, [port: port, options: tls]},
       phases: Exdock.Wire.Phases.server(),
       handshake: [required_capabilities: ["jobs.v1"]],
       readiness_timeout_ms: 35_000,
       lifecycle_observer: TCPServer},
      {Exdock.Server.Connection.Native.Registry, server: Exdock.AgentServer}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  defp generated_tls_options do
    {certificate, key} = SelfCert.generate()
    [cert: certificate, key: key, secure_renegotiate: true]
  end
end
