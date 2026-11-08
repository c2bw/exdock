defmodule Exdock.Client.Connection.RuntimeInstaller.Upgrade.RuntimeProcess do
  @moduledoc """
  Manages the runtime supervisor lifecycle during an upgrade transaction.
  """

  alias Exdock.Client.Connection.RuntimeInstaller.Context

  @spec stop(Context.t()) :: {:ok, boolean()} | {:error, term()}
  def stop(%Context{} = context) do
    with :ok <- context.ops.prepare_upgrade() do
      case context.ops.whereis(context.runtime_supervisor) do
        nil -> {:ok, false}
        pid -> stop_running(pid, context)
      end
    else
      {:error, reason} -> {:error, {:runtime_stop_failed, reason}}
    end
  end

  @spec start(module(), String.t(), pid(), Context.t()) :: :ok | {:error, term()}
  def start(runtime_module, client_name, owner, %Context{} = context)
      when is_atom(runtime_module) and is_binary(client_name) and is_pid(owner) do
    try do
      case context.ops.start(runtime_module, {client_name, owner}) do
        {:ok, pid} when is_pid(pid) -> verify_registration(pid, context)
        {:error, {:already_started, pid}} -> {:error, {:runtime_already_started, pid}}
        {:error, reason} -> {:error, {:runtime_start_failed, reason}}
      end
    rescue
      exception -> {:error, {:runtime_start_failed, {:exception, exception}}}
    catch
      kind, reason -> {:error, {:runtime_start_failed, {kind, reason}}}
    end
  end

  @spec stop_current(Context.t()) :: :ok
  def stop_current(%Context{} = context) do
    case context.ops.whereis(context.runtime_supervisor) do
      nil -> :ok
      pid -> stop_process(pid, context)
    end
  end

  defp stop_running(pid, context) do
    try do
      case context.ops.stop(pid, context.stop_timeout) do
        :ok -> {:ok, true}
        {:error, reason} -> {:error, {:runtime_stop_failed, reason}}
      end
    catch
      :exit, reason -> {:error, {:runtime_stop_failed, reason}}
    end
  end

  defp verify_registration(pid, context) do
    if context.ops.whereis(context.runtime_supervisor) == pid do
      :ok
    else
      stop_process(pid, context)
      {:error, :runtime_registration_failed}
    end
  end

  defp stop_process(pid, context) when is_pid(pid) do
    context.ops.stop(pid, context.stop_timeout)
  catch
    :exit, _reason -> :ok
  end
end
