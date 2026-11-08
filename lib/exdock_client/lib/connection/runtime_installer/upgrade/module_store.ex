defmodule Exdock.Client.Connection.RuntimeInstaller.Upgrade.ModuleStore do
  @moduledoc """
  Owns validation, loading, snapshots, and restoration of runtime modules.

  The upgrade coordinator can therefore reason about the transaction without
  also knowing the details of the VM code server.
  """

  alias Exdock.Client.Connection.RuntimeInstaller.Context
  alias Exdock.Protocol.RuntimeBundle

  @type module_entry :: {module(), binary(), String.t() | charlist()}
  @type snapshot :: Context.module_snapshot()

  @spec allowed?(term()) :: boolean()
  def allowed?(module) when is_atom(module), do: module in RuntimeBundle.required_modules()
  def allowed?(_module), do: false

  @spec preflight([module_entry()], module()) :: :ok | {:error, term()}
  def preflight(modules, ops) when is_list(modules) and is_atom(ops) do
    Enum.reduce_while(modules, :ok, fn {module, binary, _filename}, :ok ->
      case ops.beam_exports(binary) do
        {:ok, {^module, _chunks}} ->
          {:cont, :ok}

        {:ok, {actual_module, _chunks}} ->
          {:halt, {:error, {:module_name_mismatch, module, actual_module}}}

        {:error, _beam_lib, reason} ->
          {:halt, {:error, {:invalid_beam, module, reason}}}
      end
    end)
  end

  @spec snapshot([module_entry()], Context.t()) :: {:ok, snapshot()} | {:error, term()}
  def snapshot(modules, %Context{} = context) when is_list(modules) do
    snapshot = context.installed_modules || capture_loaded(modules, context.ops)

    missing =
      modules
      |> Enum.map(&elem(&1, 0))
      |> Enum.filter(&(Map.get(snapshot, &1, :unloaded) == :unloaded))

    if context.ops.whereis(context.runtime_supervisor) && missing != [] do
      {:error, {:runtime_snapshot_unavailable, missing}}
    else
      {:ok, snapshot}
    end
  end

  @spec load([module_entry()], module()) :: :ok | {:error, term()}
  def load(modules, ops) when is_list(modules) and is_atom(ops) do
    Enum.reduce_while(modules, :ok, fn
      {module, binary, filename}, :ok
      when is_atom(module) and is_binary(binary) and (is_binary(filename) or is_list(filename)) ->
        load_module(module, binary, filename, ops)

      _invalid, :ok ->
        {:halt, {:error, :invalid_module_entry}}
    end)
  end

  @spec restore(snapshot(), module()) :: :ok | {:error, term()}
  def restore(snapshot, ops) when is_map(snapshot) and is_atom(ops) do
    failures =
      Enum.reduce(snapshot, [], fn entry, failures ->
        case restore_module(entry, ops) do
          :ok -> failures
          {:error, reason} -> [reason | failures]
        end
      end)

    case Enum.reverse(failures) do
      [] -> :ok
      failures -> {:error, {:module_restore_failed, failures}}
    end
  end

  @spec purge_previous([module_entry()], module()) :: :ok
  def purge_previous(modules, ops) when is_list(modules) and is_atom(ops) do
    Enum.each(modules, fn {module, _binary, _filename} -> ops.purge(module) end)
  end

  @spec from_bundle([module_entry()]) :: snapshot()
  def from_bundle(modules) when is_list(modules) do
    Map.new(modules, fn {module, binary, filename} ->
      {module, {:loaded, binary, filename}}
    end)
  end

  defp capture_loaded(modules, ops) do
    Map.new(modules, fn {module, _binary, _filename} ->
      case ops.object_code(module) do
        {^module, binary, filename} -> {module, {:loaded, binary, filename}}
        :error -> {module, :unloaded}
      end
    end)
  end

  defp load_module(module, binary, filename, ops) do
    if allowed?(module) do
      case ops.load_binary(module, filename, binary) do
        {:module, ^module} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:module_load_failed, module, reason}}}
      end
    else
      {:halt, {:error, {:module_not_allowed, module}}}
    end
  end

  defp restore_module({module, {:loaded, binary, filename}}, ops) do
    ops.purge(module)

    case ops.load_binary(module, filename, binary) do
      {:module, ^module} ->
        ops.purge(module)
        :ok

      {:error, reason} ->
        {:error, {module, reason}}
    end
  end

  defp restore_module({module, :unloaded}, ops) do
    ops.purge(module)
    ops.delete(module)
    ops.purge(module)
    :ok
  end
end
