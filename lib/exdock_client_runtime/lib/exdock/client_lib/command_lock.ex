defmodule Exdock.ClientLib.CommandLock do
  @moduledoc """
  Worker-owned container locks survive dispatcher replacement.

  A replacement dispatcher can queue new work while an old worker finishes.
  Only the worker holding the registry key may mutate that container. A worker
  waiting for a previous owner monitors it, so failures also release the lock.
  """

  @registry Exdock.AgentRegistry

  @spec run(String.t() | nil, (-> result)) :: result when result: term()
  def run(nil, function), do: function.()

  def run(target, function) when is_binary(target) do
    key = {:container_mutation, target}
    acquire(key)

    try do
      function.()
    after
      Registry.unregister(@registry, key)
    end
  end

  defp acquire(key) do
    case Registry.register(@registry, key, nil) do
      {:ok, _} ->
        :ok

      {:error, {:already_registered, owner}} ->
        ref = Process.monitor(owner)

        receive do
          {:DOWN, ^ref, :process, ^owner, _reason} -> acquire(key)
        end
    end
  end
end
