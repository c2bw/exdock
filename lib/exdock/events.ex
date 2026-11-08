defmodule Exdock.Events do
  @moduledoc """
  Stable event boundary for runtime and UI consumers.

  All runtime and UI consumers receive revisioned envelopes on stable topics.
  """

  @behaviour Exdock.Runtime.EventSink

  alias Phoenix.PubSub
  alias Exdock.ReadModel.Projections
  alias Exdock.Runtime.EventCatalog

  @topic_prefix "exdock:"
  @type topic :: :operations | EventCatalog.topic() | {:node, String.t()}
  @type event :: {:exdock_event, topic(), non_neg_integer(), term()}

  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    subscribe_topics(EventCatalog.page_topics())
  end

  @doc """
  Subscribe a page process to its shell topics and requested projections.
  """
  @spec subscribe_page([atom()]) :: :ok | {:error, term()}
  def subscribe_page(projections) when is_list(projections) do
    projection_topics = Projections.topics(projections)
    subscribe_topics(Enum.uniq(EventCatalog.base_page_topics() ++ projection_topics))
  end

  @spec subscribe(topic()) :: :ok | {:error, term()}
  def subscribe(topic), do: PubSub.subscribe(Exdock.PubSub, topic_name(topic))

  @spec publish(topic(), term()) :: :ok
  def publish(topic, payload) do
    publish_if_available(topic, {:exdock_event, topic, revision(), payload})
  end

  @spec publish(topic(), non_neg_integer(), term()) :: :ok
  def publish(topic, revision, payload) when is_integer(revision) and revision >= 0 do
    publish_if_available(topic, {:exdock_event, topic, revision, payload})
  end

  @spec operation_accepted(Ecto.UUID.t(), atom()) :: :ok
  def operation_accepted(operation_id, kind) when is_binary(operation_id) and is_atom(kind) do
    publish(:operations, %{id: operation_id, kind: kind, state: :accepted})
  end

  @spec operation_finished(Ecto.UUID.t(), atom(), term()) :: :ok
  def operation_finished(operation_id, kind, result)
      when is_binary(operation_id) and is_atom(kind) do
    publish(:operations, %{id: operation_id, kind: kind, state: :finished, result: result})
  end

  defp publish_if_available(topic, event) do
    if Process.whereis(Exdock.PubSub) do
      PubSub.broadcast(Exdock.PubSub, topic_name(topic), event)
    else
      :ok
    end
  end

  defp subscribe_topics(topics) do
    Exdock.Result.each(topics, &subscribe/1)
  end

  defp topic_name({:node, node}) when is_binary(node), do: @topic_prefix <> "node:" <> node
  defp topic_name(topic) when is_atom(topic), do: @topic_prefix <> Atom.to_string(topic)

  defp revision, do: System.unique_integer([:monotonic, :positive])
end
