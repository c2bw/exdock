defmodule Exdock.Runtime.EventCatalog do
  @moduledoc """
  Canonical routing metadata for revisioned runtime event sources.

  The catalog contains data only so state producers, read-model consumers, and
  the PubSub boundary can share one vocabulary without introducing compile
  dependencies between those layers.
  """

  @source_specs %{
    settings: %{topic: :settings, consumer: :assigns, revision: :runtime, base_page?: true},
    tags: %{topic: :repositories, consumer: :routing_only, revision: :runtime, base_page?: false},
    repositories: %{topic: :repositories, consumer: :assigns, revision: :runtime, base_page?: false},
    nodes: %{topic: :cluster, consumer: :assigns, revision: :runtime, base_page?: false},
    images: %{topic: :cluster, consumer: :assigns, revision: :runtime, base_page?: false},
    containers: %{topic: :cluster, consumer: :assigns, revision: :runtime, base_page?: false},
    cluster_info: %{topic: :cluster, consumer: :assigns, revision: :runtime, base_page?: false},
    server_configuration: %{topic: :cluster, consumer: :assigns, revision: :runtime, base_page?: true},
    status: %{topic: :activity, consumer: :assigns, revision: :activity, base_page?: true},
    log: %{topic: :activity, consumer: :assigns, revision: :activity, base_page?: true}
  }

  @type source ::
          :settings
          | :tags
          | :repositories
          | :nodes
          | :images
          | :containers
          | :cluster_info
          | :server_configuration
          | :status
          | :log

  @type topic :: :cluster | :settings | :repositories | :activity
  @type consumer_policy :: :assigns | :routing_only
  @type revision_scope :: :runtime | :activity

  @spec sources() :: [source()]
  def sources, do: Map.keys(@source_specs)

  @spec topic_for_source(term()) :: {:ok, topic()} | :error
  def topic_for_source(source) do
    case Map.fetch(@source_specs, source) do
      {:ok, spec} -> {:ok, spec.topic}
      :error -> :error
    end
  end

  @spec topic_for_source!(source()) :: topic()
  def topic_for_source!(source), do: @source_specs |> Map.fetch!(source) |> Map.fetch!(:topic)

  @spec known_source?(term()) :: boolean()
  def known_source?(source), do: Map.has_key?(@source_specs, source)

  @spec consumer_policy_for(term()) :: {:ok, consumer_policy()} | :error
  def consumer_policy_for(source) do
    case Map.fetch(@source_specs, source) do
      {:ok, spec} -> {:ok, spec.consumer}
      :error -> :error
    end
  end

  @spec sources_for_revision(revision_scope()) :: [source()]
  def sources_for_revision(scope) when scope in [:runtime, :activity] do
    sources_matching(:revision, scope)
  end

  @spec sources_for_consumer(consumer_policy()) :: [source()]
  def sources_for_consumer(policy) when policy in [:assigns, :routing_only] do
    sources_matching(:consumer, policy)
  end

  @spec base_page_topics() :: [topic()]
  def base_page_topics do
    @source_specs
    |> Enum.filter(fn {_source, spec} -> spec.base_page? end)
    |> Enum.map(fn {_source, spec} -> spec.topic end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @spec page_topics() :: [topic()]
  def page_topics do
    @source_specs
    |> Map.values()
    |> Enum.map(&Map.fetch!(&1, :topic))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp sources_matching(field, value) do
    @source_specs
    |> Enum.filter(fn {_source, spec} -> Map.fetch!(spec, field) == value end)
    |> Enum.map(&elem(&1, 0))
  end
end
