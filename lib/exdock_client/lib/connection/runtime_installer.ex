defmodule Exdock.Client.Connection.RuntimeInstaller do
  @moduledoc """
  Serializes validation and installation of server-supplied agent runtimes.

  Installation requests are serialized here while the upgrade transaction is
  owned by `RuntimeInstaller.Upgrade`. The last successful bundle remains in
  process state as a rollback snapshot.
  """

  use GenServer

  alias Exdock.Client.Connection.RuntimeInstaller.{Context, SystemOps, Upgrade}
  alias Exdock.Protocol.RuntimeBundle

  @runtime_supervisor Exdock.ClientLib
  @install_timeout 30_000

  @enforce_keys [:ops, :runtime_supervisor]
  defstruct [:installed_modules, :ops, :runtime_supervisor]

  @type t :: %__MODULE__{
          installed_modules: Context.module_snapshot() | nil,
          ops: module(),
          runtime_supervisor: atom()
        }

  def start_link(opts \\ []) when is_list(opts) do
    {name, init_opts} = Keyword.pop(opts, :name, __MODULE__)
    start_opts = if is_nil(name), do: [], else: [name: name]
    GenServer.start_link(__MODULE__, init_opts, start_opts)
  end

  @impl true
  def init(opts) do
    {:ok,
     %__MODULE__{
       installed_modules: nil,
       ops: Keyword.get(opts, :ops, SystemOps),
       runtime_supervisor: Keyword.get(opts, :runtime_supervisor, @runtime_supervisor)
     }}
  end

  @spec install(map(), String.t(), module(), GenServer.server()) :: :ok | {:error, term()}
  def install(bundle, client_name, runtime_module \\ Exdock.AgentRuntime, server \\ __MODULE__)

  def install(bundle, client_name, runtime_module, server)
      when is_map(bundle) and is_binary(client_name) and is_atom(runtime_module) do
    GenServer.call(server, {:install, bundle, client_name, runtime_module}, @install_timeout)
  catch
    :exit, {:noproc, _call} -> {:error, {:installer_unavailable, :not_found}}
    :exit, {:timeout, _call} -> {:error, {:installer_unavailable, :timeout}}
    :exit, reason -> {:error, {:installer_failure, reason}}
  end

  def install(_bundle, _client_name, _runtime_module, _server), do: {:error, :invalid_runtime_bundle}

  @spec allowed_module?(module()) :: boolean()
  def allowed_module?(module) when is_atom(module), do: module in RuntimeBundle.required_modules()
  def allowed_module?(_module), do: false

  @impl true
  def handle_call({:install, bundle, client_name, runtime_module}, {owner, _tag}, %__MODULE__{} = state) do
    context = %Context{
      installed_modules: state.installed_modules,
      ops: state.ops,
      runtime_supervisor: state.runtime_supervisor
    }

    case Upgrade.install(bundle, client_name, runtime_module, owner, context) do
      {:ok, installed_modules} ->
        {:reply, :ok, %{state | installed_modules: installed_modules}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
end
