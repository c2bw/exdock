defmodule Exdock.Server.Jobs.Local.Registry.FetchReport do
  @moduledoc """
  Complete outcome of a concurrent registry metadata fetch.

  Failed requests still contribute fallback tag metadata, while request
  failures and task exits remain visible to the orchestration boundary.
  """

  alias Exdock.Domain.TagInfo
  alias Exdock.Server.Jobs.TaskStream

  defstruct tags: [], request_failures: [], worker_exits: []

  @type request_failure :: %{
          required(:tag) => String.t(),
          required(:platform) => String.t(),
          required(:reason) => term()
        }

  @type t :: %__MODULE__{
          tags: [TagInfo.t()],
          request_failures: [request_failure()],
          worker_exits: [term()]
        }

  @spec collect(Enumerable.t()) :: t()
  def collect(outcomes) do
    outcomes
    |> TaskStream.collect()
    |> from_task_stream()
  end

  @spec from_bucket_stream(TaskStream.t(t())) :: t()
  def from_bucket_stream(%TaskStream{values: reports, exits: exits}) do
    reports
    |> Enum.reduce(new(), &merge_reversed(&2, &1))
    |> restore_order()
    |> add_worker_exits(exits)
  end

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec error(t()) :: nil | {:registry_fetch_failed, map()}
  def error(%__MODULE__{request_failures: [], worker_exits: []}), do: nil

  def error(%__MODULE__{request_failures: failures, worker_exits: exits}) do
    {:registry_fetch_failed, %{request_failures: failures, worker_exits: exits}}
  end

  defp from_task_stream(%TaskStream{values: outcomes, exits: exits}) do
    outcomes
    |> Enum.reduce(new(), &add_outcome(&2, &1))
    |> restore_order()
    |> add_worker_exits(exits)
  end

  defp add_outcome(%__MODULE__{} = report, {:ok, %TagInfo{} = tag_info}) do
    %{report | tags: [tag_info | report.tags]}
  end

  defp add_outcome(
         %__MODULE__{} = report,
         {:error, reason, %TagInfo{tag: tag, platform: platform} = tag_info}
       ) do
    failure = %{tag: tag, platform: platform, reason: reason}

    %{
      report
      | tags: [tag_info | report.tags],
        request_failures: [failure | report.request_failures]
    }
  end

  defp merge_reversed(%__MODULE__{} = accumulator, %__MODULE__{} = report) do
    %__MODULE__{
      tags: Enum.reverse(report.tags, accumulator.tags),
      request_failures: Enum.reverse(report.request_failures, accumulator.request_failures),
      worker_exits: Enum.reverse(report.worker_exits, accumulator.worker_exits)
    }
  end

  defp restore_order(%__MODULE__{} = report) do
    %__MODULE__{
      tags: Enum.reverse(report.tags),
      request_failures: Enum.reverse(report.request_failures),
      worker_exits: Enum.reverse(report.worker_exits)
    }
  end

  defp add_worker_exits(%__MODULE__{} = report, exits) when is_list(exits) do
    %{report | worker_exits: report.worker_exits ++ exits}
  end
end
