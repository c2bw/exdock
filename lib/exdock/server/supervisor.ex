defmodule Exdock.Server.Supervisor do
  @moduledoc """
  Supervises the Exdock backend in dependency order.

  A `:rest_for_one` strategy restarts processes downstream of a failed state
  owner or job engine while preserving independent upstream infrastructure.
  """

  use Supervisor

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(args) do
    tcp_port = Keyword.fetch!(args, :tcp_port)
    auth_key = Keyword.fetch!(args, :auth_key)

    children = [
      {Exdock.Database.Vault, name: Exdock.Database.Vault},
      {Exdock.Server.Broadcast, name: Exdock.Server.Broadcast},
      {Exdock.Server, args},
      {Exdock.Server.AutomationScheduler, name: Exdock.Server.AutomationScheduler},
      {Exdock.Docker.Remote.RegistryClient, name: Exdock.Docker.Remote.RegistryClient},
      {Exdock.Server.RegistryFetchLimiter, name: Exdock.Server.RegistryFetchLimiter},
      {Exdock.Server.Jobs.Supervisor, []},
      {Exdock.Server.Logging, name: Exdock.Server.Logging},
      {Exdock.Server.Notifier, name: Exdock.Server.Notifier},
      {Exdock.Server.Connection.Supervisor, {auth_key, tcp_port}}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
