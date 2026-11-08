defmodule Exdock.Docker.Remote.RegistryClient do
  @moduledoc """
  Owns the reusable `Regc.Client` used for remote registry operations.

  Reusing one client preserves authentication state and allows Regc to pool
  idle registry connections across image refresh jobs.
  """

  use GenServer

  alias Regc.Client

  @doc """
  Starts the registry client owner.

  Passing `name: nil` starts an unregistered process for isolated tests.
  Remaining options are passed to `Regc.Client.new/1`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, client_opts} = Keyword.pop(opts, :name, __MODULE__)

    case name do
      nil -> GenServer.start_link(__MODULE__, client_opts)
      name -> GenServer.start_link(__MODULE__, client_opts, name: name)
    end
  end

  @doc """
  Returns the shared immutable client configuration.
  """
  @spec get(GenServer.server()) :: Client.t()
  def get(server \\ __MODULE__), do: GenServer.call(server, :get)

  @impl true
  def init(client_opts) do
    client = Client.new(client_opts)
    Process.link(client.state)
    {:ok, client}
  end

  @impl true
  def handle_call(:get, _from, client), do: {:reply, client, client}

  @impl true
  def terminate(_reason, client) do
    Client.close(client)
  end
end
