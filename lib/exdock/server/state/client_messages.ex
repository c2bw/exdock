defmodule Exdock.Server.State.ClientMessages do
  @moduledoc """
  Routes authenticated client messages to focused state reducers.

  Client messages are already authenticated and decoded by the TCP handler.
  This module owns the shared message envelope while domain reducers own the
  state and effect changes for each result family.
  """

  alias Exdock.Protocol.Messages
  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.Catalog
  alias Exdock.Server.Jobs.Job
  alias Exdock.Server.State
  alias Exdock.Server.State.ClientMessages.AsyncResources
  alias Exdock.Server.State.ClientMessages.ContainerJobs
  alias Exdock.Server.State.ClientMessages.NodeRefresh
  alias Exdock.Server.State.ClientMessages.NodeRefresh.Prepared, as: PreparedNodeRefresh
  alias Exdock.Server.State.Effects
  alias Exdock.Server.State.Transition

  @type result :: {State.t(), [Effects.effect()]}
  @type reduction :: result() | PreparedNodeRefresh.t()

  @spec reduce(State.t(), term(), DateTime.t()) :: reduction()
  def reduce(
        %State{} = state,
        %Messages.JobResult{job: %Job{name: name}} = message,
        %DateTime{} = occurred_at
      ) do
    case Catalog.client_result_handler(name) do
      :node_refresh -> NodeRefresh.reduce(state, message, occurred_at)
      :container -> ContainerJobs.reduce(state, message, occurred_at)
      nil -> unsupported(state, message)
    end
  end

  def reduce(
        %State{} = state,
        %Messages.Update{
          id: id,
          name: name,
          node: node,
          data: data
        },
        %DateTime{}
      ) do
    {state, [{:job_info, Jobs.Message.new(id, name, node, data)}]}
  end

  def reduce(%State{} = state, %Messages.AsyncResult{} = message, %DateTime{}),
    do: AsyncResources.reduce(state, message)

  def reduce(%State{} = state, message, %DateTime{}), do: unsupported(state, message)

  defp unsupported(%State{} = state, message) do
    effect =
      {:log, :warning, "Ignoring unsupported authenticated client message: #{inspect(message_kind(message))}"}

    {state, [effect]}
  end

  @spec commit(State.t(), term()) :: State.t()
  def commit(%State{} = state, message) do
    commit(state, message, DateTime.utc_now(), [])
  end

  @spec commit(State.t(), term(), DateTime.t()) :: State.t()
  def commit(%State{} = state, message, %DateTime{} = occurred_at) do
    commit(state, message, occurred_at, [])
  end

  @spec commit(State.t(), term(), DateTime.t(), keyword()) :: State.t()
  def commit(%State{} = state, message, %DateTime{} = occurred_at, opts) when is_list(opts) do
    state
    |> reduce(message, occurred_at)
    |> materialize()
    |> Transition.commit_pair(opts)
  end

  defp materialize(%PreparedNodeRefresh{} = prepared),
    do: PreparedNodeRefresh.execute(prepared)

  defp materialize({%State{}, effects} = result) when is_list(effects), do: result

  defp message_kind(%{__struct__: module}) when is_atom(module), do: module
  defp message_kind(message), do: typeof(message)

  defp typeof(value) when is_atom(value), do: :atom
  defp typeof(value) when is_binary(value), do: :binary
  defp typeof(value) when is_list(value), do: :list
  defp typeof(value) when is_map(value), do: :map
  defp typeof(value) when is_tuple(value), do: :tuple
  defp typeof(_value), do: :other
end
