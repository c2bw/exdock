defmodule Exdock.Application do
  @moduledoc """
  OTP entrypoint for the Phoenix host application.

  Startup does a small amount of release housekeeping, reads runtime settings,
  then starts the web-facing processes and the backend server runtime under the
  same top-level supervisor. The backend server is optional so tests and narrow
  tooling can boot Phoenix without opening the TCP listener.
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    package_version = Application.spec(:exdock, :vsn) |> to_string()
    protocol_version = Exdock.Protocol.Contract.current_version()

    Logger.info("Starting Exdock server package_version=#{package_version} protocol_version=#{protocol_version}")

    # Release tasks are safe to run on every boot; they make a packaged release
    # self-initializing without requiring an operator to run mix tasks manually.
    Exdock.Release.create()
    Exdock.Release.migrate()

    # Runtime configuration is fetched once at the application boundary and then
    # passed into supervised children, keeping process init callbacks explicit.
    fetch_env = fn var ->
      case Application.fetch_env(:exdock, var) do
        {:ok, val} ->
          val

        :error ->
          Logger.error("Error fetching environment variable: #{var}")
          exit({:error, :env_fetch_error})
      end
    end

    tcp_port = fetch_env.(:tcp_server_port)
    auth_key = fetch_env.(:auth_key)
    ui_email = fetch_env.(:ui_email)
    ui_psw = fetch_env.(:ui_password)

    children =
      [
        {Registry, keys: :unique, name: Exdock.AgentRegistry},
        ExdockWeb.Telemetry,
        {Exdock.Server.TelemetryReporter,
         metrics: ExdockWeb.Telemetry.metrics(), wanted_events: [[:phoenix, :live_view, :render, :stop]]},
        Supervisor.child_spec({Phoenix.PubSub, name: Exdock.PubSub}, id: Exdock.PubSub),
        Exdock.Repo,
        {ExdockWeb.LoginRateLimiter, Application.fetch_env!(:exdock, :login_rate_limit)},
        server_child(tcp_port, auth_key, ui_email, ui_psw),
        # Keep the endpoint last so dependencies such as PubSub and Repo are
        # ready before HTTP and LiveView traffic can arrive.
        ExdockWeb.Endpoint
      ]
      |> Enum.reject(&is_nil/1)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Exdock.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ExdockWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp server_child(tcp_port, auth_key, ui_email, ui_psw) do
    if Application.get_env(:exdock, :start_server, true) do
      {Exdock.Server.Supervisor, tcp_port: tcp_port, auth_key: auth_key, email: ui_email, plain_password: ui_psw}
    end
  end
end
