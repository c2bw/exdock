defmodule Exdock.Client.Connection.RuntimeInstaller.Upgrade do
  @moduledoc """
  Coordinates one validated agent-runtime upgrade transaction.

  Module storage and runtime process lifecycle are separate boundaries, leaving
  this module responsible only for sequencing and rollback policy.
  """

  alias Exdock.Client.Connection.RuntimeInstaller.Context
  alias Exdock.Client.Connection.RuntimeInstaller.Upgrade.{ModuleStore, RuntimeProcess}
  alias Exdock.Protocol.RuntimeBundle

  @type module_snapshot :: Context.module_snapshot()

  @spec install(map(), String.t(), module(), pid(), Context.t()) ::
          {:ok, module_snapshot()} | {:error, term()}
  def install(%{"modules" => modules} = bundle, client_name, runtime_module, owner, %Context{} = context)
      when is_list(modules) and is_binary(client_name) and is_atom(runtime_module) and is_pid(owner) do
    with :ok <- RuntimeBundle.validate(bundle, &ModuleStore.allowed?/1),
         :ok <- ModuleStore.preflight(modules, context.ops),
         {:ok, snapshot} <- ModuleStore.snapshot(modules, context),
         {:ok, runtime_was_running?} <- RuntimeProcess.stop(context) do
      replace_runtime(
        modules,
        snapshot,
        runtime_was_running?,
        runtime_module,
        client_name,
        owner,
        context
      )
    end
  end

  def install(_bundle, _client_name, _runtime_module, _owner, _opts),
    do: {:error, :invalid_runtime_bundle}

  defp replace_runtime(
         modules,
         snapshot,
         runtime_was_running?,
         runtime_module,
         client_name,
         owner,
         context
       ) do
    result =
      with :ok <- ModuleStore.load(modules, context.ops),
           :ok <- RuntimeProcess.start(runtime_module, client_name, owner, context) do
        :ok
      end

    case result do
      :ok ->
        ModuleStore.purge_previous(modules, context.ops)
        {:ok, ModuleStore.from_bundle(modules)}

      {:error, reason} ->
        rollback(
          reason,
          snapshot,
          runtime_was_running?,
          runtime_module,
          client_name,
          owner,
          context
        )
    end
  end

  defp rollback(
         reason,
         snapshot,
         runtime_was_running?,
         runtime_module,
         client_name,
         owner,
         context
       ) do
    RuntimeProcess.stop_current(context)
    restore_result = ModuleStore.restore(snapshot, context.ops)

    restart_result =
      if restore_result == :ok and runtime_was_running? do
        RuntimeProcess.start(runtime_module, client_name, owner, context)
      else
        :ok
      end

    case {restore_result, restart_result} do
      {:ok, :ok} -> {:error, reason}
      rollback -> {:error, {:runtime_upgrade_failed, reason, rollback}}
    end
  end
end
