defmodule Exdock.Server.State.Storage.Containers.Info do
  @moduledoc """
  Aggregated counters used by container summary widgets.

  The same structure is computed for all containers, running containers, and
  stopped containers so pages can render comparable dashboard sections.
  """

  alias Exdock.Server.State.Storage.Containers.Info.Counters
  alias Exdock.Server.State.Storage.Containers.Info.Data
  alias Exdock.Domain
  alias Exdock.Domain.Container
  alias Exdock.Domain.Container.Core

  @status_buckets [:errored, :unknown, :outdated, :updated]
  @priority_buckets [:ignore, :low, :normal, :high, :to_update]

  defstruct [
    :combined,
    :running,
    :stopped
  ]

  @type t :: %__MODULE__{
          combined: Data.t(),
          running: Data.t(),
          stopped: Data.t()
        }

  @spec new(list(Domain.Container.t())) :: t()
  def new(containers) when is_list(containers) do
    summaries = Enum.reduce(containers, empty_summaries(), &add_container/2)

    %__MODULE__{
      combined: summary_data(summaries.combined),
      running: summary_data(summaries.running),
      stopped: summary_data(summaries.stopped)
    }
  end

  @spec summary_data(map()) :: Data.t()
  defp summary_data(summary) do
    %Data{
      stacks_count: MapSet.size(summary.stack_names),
      containers_count: summary.containers_count,
      latest_started_at: summary.latest_started_at,
      restarting?: summary.restarting?,
      counters: %Counters{
        status: status_counters(summary.status_counts, summary.containers_count),
        priority: summary.priority_counts
      }
    }
  end

  defp empty_summaries do
    %{combined: initial_summary(), running: initial_summary(), stopped: initial_summary()}
  end

  defp add_container(%Container{} = container, summaries) do
    # Keep the three dashboard buckets in one pass so status/priority logic
    # cannot drift between the combined, running, and stopped summaries.
    summaries
    |> add_to_summary(:combined, container)
    |> add_to_runtime_summary(container)
  end

  defp add_to_runtime_summary(summaries, %Container{} = container) do
    if Container.running?(container) do
      add_to_summary(summaries, :running, container)
    else
      add_to_summary(summaries, :stopped, container)
    end
  end

  defp add_to_summary(summaries, key, %Container{} = container) do
    Map.update!(summaries, key, &summarize_container(container, &1))
  end

  defp summarize_container(
         %Container{core: %Core{stack_name: stack_name}} = container,
         summary
       ) do
    image_status = Container.image_status(container)

    %{
      summary
      | containers_count: summary.containers_count + 1,
        status_counts: count_status(image_status, summary.status_counts),
        priority_counts: count_priority(image_status, container, summary.priority_counts),
        latest_started_at: latest_started_at(summary.latest_started_at, container),
        restarting?: summary.restarting? || Container.restarting?(container),
        stack_names: add_stack(summary.stack_names, stack_name)
    }
  end

  defp initial_summary do
    %{
      containers_count: 0,
      status_counts: empty_bucket_counts(@status_buckets),
      priority_counts: empty_bucket_counts(@priority_buckets),
      latest_started_at: nil,
      restarting?: false,
      stack_names: MapSet.new()
    }
  end

  defp add_stack(stack_names, stack_name) when is_binary(stack_name) and stack_name != "" do
    MapSet.put(stack_names, stack_name)
  end

  defp add_stack(stack_names, _stack_name), do: stack_names

  defp latest_started_at(
         current,
         %Container{core: %Core{is_running: true, state: %Core.State{started_at: %DateTime{} = started_at}}}
       ) do
    case current do
      %DateTime{} -> if(DateTime.after?(started_at, current), do: started_at, else: current)
      nil -> started_at
    end
  end

  defp latest_started_at(current, %Container{}), do: current

  defp status_counters(status_counts, containers_count) do
    Map.new(@status_buckets, fn status ->
      {status, count_bucket(status_counts[status], containers_count)}
    end)
  end

  defp count_bucket(count, total) do
    %{count: count, percentage: percentage(count, total)}
  end

  defp count_status(status, status_counts) do
    increment_bucket(status_counts, status_bucket_name(status))
  end

  defp empty_bucket_counts(buckets), do: Map.new(buckets, &{&1, 0})

  defp status_bucket_name(:unknown), do: :unknown
  defp status_bucket_name(:outdated), do: :outdated
  defp status_bucket_name(:updated), do: :updated
  defp status_bucket_name(_), do: :errored

  defp count_priority(:outdated, %Container{} = container, priority_counts) do
    increment_bucket(priority_counts, priority_bucket(container))
  end

  defp count_priority(_image_status, %Container{} = _container, priority_counts) do
    priority_counts
  end

  defp increment_bucket(counts, bucket), do: Map.update!(counts, bucket, &(&1 + 1))

  defp priority_bucket(%Container{} = container) do
    case Container.priority(container) do
      1 -> :ignore
      2 -> :low
      3 -> :normal
      4 -> :high
      5 -> :to_update
    end
  end

  defp percentage(_count, 0), do: 0
  defp percentage(count, total), do: Float.ceil(count / total * 100, 1)
end
