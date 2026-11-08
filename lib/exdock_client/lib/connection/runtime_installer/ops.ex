defmodule Exdock.Client.Connection.RuntimeInstaller.Ops do
  @moduledoc "Low-level code loading and runtime process operations used during upgrades."

  @callback beam_exports(binary()) :: {:ok, {module(), term()}} | {:error, term(), term()}
  @callback object_code(module()) :: {module(), binary(), charlist()} | :error
  @callback load_binary(module(), String.t() | charlist(), binary()) :: {:module, module()} | {:error, term()}
  @callback purge(module()) :: boolean()
  @callback delete(module()) :: boolean()
  @callback whereis(atom()) :: pid() | nil
  @callback prepare_upgrade() :: :ok | {:error, :runtime_busy}
  @callback stop(pid(), timeout()) :: :ok
  @callback start(module(), term()) :: {:ok, pid()} | {:error, term()}
end
