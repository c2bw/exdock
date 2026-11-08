defmodule Exdock.Server.State.Storage.Images.Info do
  @moduledoc """
  Aggregated counters used by image inventory summary widgets.

  The structure is computed for all images plus useful subsets such as unused
  and in-use images.
  """

  alias Exdock.Server.State.Storage.Images.Info.Counters
  alias Exdock.Server.State.Storage.Images.Info.Data
  alias Exdock.Domain
  alias Exdock.Domain.Image

  @status_buckets [:locked, :unused, :in_use]

  defstruct [
    :combined,
    :unused,
    :in_use
  ]

  @type t :: %__MODULE__{
          combined: Data.t(),
          unused: Data.t(),
          in_use: Data.t()
        }

  @spec new(list(Domain.Image.t())) :: t()
  def new(images) when is_list(images) do
    summaries = Enum.reduce(images, empty_summaries(), &add_image/2)

    %__MODULE__{
      combined: data(summaries.combined),
      unused: data(summaries.unused),
      in_use: data(summaries.in_use)
    }
  end

  defp data(summary) do
    %Data{
      total_bytesize: summary.total_bytesize,
      shared_bytesize: summary.shared_bytesize,
      images_count: summary.images_count,
      counters: %Counters{status: status_counters(summary.status_counts, summary.images_count)}
    }
  end

  defp empty_summaries do
    %{combined: initial_summary(), unused: initial_summary(), in_use: initial_summary()}
  end

  defp initial_summary do
    %{
      total_bytesize: 0,
      shared_bytesize: 0,
      images_count: 0,
      status_counts: Map.new(@status_buckets, &{&1, 0})
    }
  end

  defp add_image(%Image{} = image, summaries) do
    # Maintain the three public summaries in one pass so their filtering rules
    # stay beside the shared size/status aggregation.
    summaries
    |> add_to_summary(:combined, image)
    |> maybe_add_to_summary(:unused, image, unused?(image))
    |> maybe_add_to_summary(:in_use, image, Image.in_use?(image))
  end

  defp add_to_summary(summaries, key, %Image{} = image) do
    Map.update!(summaries, key, &summarize_image(image, &1))
  end

  defp maybe_add_to_summary(summaries, key, %Image{} = image, true), do: add_to_summary(summaries, key, image)
  defp maybe_add_to_summary(summaries, _key, %Image{}, false), do: summaries

  defp summarize_image(%Image{} = image, summary) do
    %{
      summary
      | total_bytesize: summary.total_bytesize + image.size,
        shared_bytesize: summary.shared_bytesize + image.shared_size,
        images_count: summary.images_count + 1,
        status_counts: count_statuses(image, summary.status_counts)
    }
  end

  defp status_counters(status_counts, images_count) do
    Map.new(@status_buckets, &status_counter_entry(&1, status_counts, images_count))
  end

  defp status_counter_entry(status, status_counts, images_count) do
    count = status_counts[status]
    {status, %{count: count, percentage: percentage(count, images_count)}}
  end

  defp count_statuses(%Image{} = image, status_counts) do
    status_counts
    |> count_if(:locked, Image.locked?(image))
    |> count_if(:unused, unused?(image))
    |> count_if(:in_use, Image.in_use?(image))
  end

  defp count_if(counts, status, true), do: Map.update!(counts, status, &(&1 + 1))
  defp count_if(counts, _status, false), do: counts

  defp unused?(%Image{} = image) do
    not Image.locked?(image) and not Image.in_use?(image)
  end

  defp percentage(_count, 0), do: 0
  defp percentage(count, total), do: Float.ceil(count / total * 100, 1)
end
