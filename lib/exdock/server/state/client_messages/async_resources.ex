defmodule Exdock.Server.State.ClientMessages.AsyncResources do
  @moduledoc false

  alias Exdock.Protocol.Messages
  alias Exdock.Server.State
  alias Exdock.Server.State.Change.Outcome
  alias Exdock.Server.State.Storage
  alias Exdock.Domain.Container.Resources.Record

  @spec reduce(State.t(), Messages.AsyncResult.t()) ::
          Exdock.Server.State.ClientMessages.result()
  def reduce(
        %State{} = state,
        %Messages.AsyncResult{
          node: node,
          id: id,
          name: :container_resources,
          result: result
        }
      ) do
    case normalize_sample(result) do
      {:ok, %Record{} = record} ->
        reduce_change(state, Storage.Containers.Change.resources(node, id, record))

      :error ->
        {state, [log(:warning, "Ignoring malformed container resource sample for #{id}")]}
    end
  end

  defp normalize_sample(%Record{} = record), do: {:ok, record}

  defp normalize_sample(sample) when is_map(sample) do
    case Record.new(sample) do
      %Record{} = record -> {:ok, record}
      nil -> :error
    end
  end

  defp normalize_sample(_sample), do: :error

  defp reduce_change(%State{} = state, mutation) do
    case State.Change.reduce(state, mutation) do
      %Outcome{state: updated_state, effects: effects} ->
        {updated_state, effects}

      {:error, reason, unchanged_state} ->
        {unchanged_state, [log(:error, "State mutation rejected: #{inspect(reason)}")]}
    end
  end

  defp log(level, message), do: {:log, level, message}
end
