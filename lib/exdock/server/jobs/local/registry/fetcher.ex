defmodule Exdock.Server.Jobs.Local.Registry.Fetcher do
  @moduledoc """
  Concurrent remote registry fetch execution.

  Requests are bucketed by registry endpoint so each endpoint receives a
  bounded worker pool while the shared limiter caps overlapping jobs.
  """

  require Logger
  alias Exdock.Datetime
  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.TaskStream
  alias Exdock.Server.Jobs.Local.Registry.{Context, FetchReport, RequestBuckets}
  alias Exdock.Server.State.Storage
  alias Exdock.Domain

  @spec fetch(
          [%{tag: String.t(), platform: String.t()}],
          Storage.TagsInfo.t(),
          String.t()
        ) :: {:ok, FetchReport.t()}
  def fetch(image_requests, %Storage.TagsInfo{} = tags_info, job_id) do
    fetch(image_requests, tags_info, job_id, Context.default())
  end

  @doc """
  Fetches registry metadata using explicit runtime collaborators.

  This entry point is useful for deterministic execution and tests. Production
  callers normally use `fetch/3`, which supplies `Context.default/0`.
  """
  @spec fetch(
          [%{tag: String.t(), platform: String.t()}],
          Storage.TagsInfo.t(),
          String.t(),
          Context.t()
        ) :: {:ok, FetchReport.t()}
  def fetch(image_requests, %Storage.TagsInfo{} = tags_info, job_id, %Context{} = context) do
    report =
      image_requests
      |> stream_remote_tag_results(tags_info, job_id, context)

    {:ok, report}
  end

  defp stream_remote_tag_results(
         image_requests,
         %Storage.TagsInfo{} = tags_info,
         job_id,
         %Context{} = context
       ) do
    %RequestBuckets{buckets: buckets, max_concurrency: max_concurrency} =
      RequestBuckets.plan(image_requests)

    buckets
    |> Task.async_stream(
      fn requests ->
        requests
        |> Task.async_stream(
          &fetch_remote_info(&1, tags_info, job_id, context),
          ordered: false,
          max_concurrency: context.max_concurrency,
          timeout: :infinity
        )
        |> FetchReport.collect()
      end,
      ordered: false,
      max_concurrency: max_concurrency,
      timeout: :infinity
    )
    |> TaskStream.collect()
    |> FetchReport.from_bucket_stream()
  end

  @spec collect_report(Enumerable.t()) :: FetchReport.t()
  def collect_report(stream), do: FetchReport.collect(stream)

  @spec fetch_tag(
          String.t(),
          String.t(),
          Domain.TagInfo.t() | nil,
          String.t(),
          (String.t(), String.t(), Domain.TagInfo.t() | nil ->
             Domain.TagInfo.t()),
          (Jobs.Update.t() -> term())
        ) :: {:ok, Domain.TagInfo.t()} | {:error, term(), Domain.TagInfo.t()}
  def fetch_tag(
        image_tag,
        platform,
        previous_tag_info,
        job_id,
        fetch_fun,
        update_fun
      )
      when is_binary(image_tag) and is_binary(platform) and is_binary(job_id) and
             is_function(fetch_fun, 3) and is_function(update_fun, 1) do
    fetch_tag_with_clock(
      image_tag,
      platform,
      previous_tag_info,
      job_id,
      fetch_fun,
      update_fun,
      &DateTime.utc_now/0
    )
  end

  defp fetch_remote_info(
         %{tag: image_tag, platform: platform},
         %Storage.TagsInfo{} = tags_info,
         job_id,
         %Context{} = context
       ) do
    previous_tag_info = Storage.TagsInfo.get(tags_info, image_tag, platform)

    fetch_tag_with_clock(
      image_tag,
      platform,
      previous_tag_info,
      job_id,
      fn image_tag, platform, previous_tag_info ->
        {remote_digest, remote_date} =
          Context.lookup_metadata(context, image_tag, platform, previous_tag_info)

        Logger.debug("Remote Info [#{image_tag}]: digest=[#{inspect(remote_digest)}] date=[#{to_string(remote_date)}]")

        Domain.TagInfo.new(
          image_tag,
          platform,
          remote_digest,
          remote_date,
          Context.now(context)
        )
      end,
      &Context.publish_update(context, &1),
      fn -> Context.now(context) end
    )
  end

  defp fetch_tag_with_clock(
         image_tag,
         platform,
         previous_tag_info,
         job_id,
         fetch_fun,
         update_fun,
         clock
       ) do
    try do
      tag_info = fetch_fun.(image_tag, platform, previous_tag_info)
      update_fun.(Jobs.Update.new(job_id, nil, image_tag, false))
      {:ok, tag_info}
    rescue
      error ->
        publish_fetch_error(update_fun, clock, job_id, image_tag, platform, error)
    catch
      kind, reason ->
        publish_fetch_error(update_fun, clock, job_id, image_tag, platform, {kind, reason})
    end
  end

  defp publish_fetch_error(update_fun, clock, job_id, image_tag, platform, error) do
    Logger.warning("Registry: failed to fetch [#{image_tag}] for [#{platform}]: #{inspect(error)}")

    update_fun.(Jobs.Update.new(job_id, nil, image_tag, false, error))
    {:error, error, errored_tag_info(image_tag, platform, clock.())}
  end

  defp errored_tag_info(image_tag, platform, check_date) do
    Domain.TagInfo.new(
      image_tag,
      platform,
      "",
      Datetime.unix_epoch(),
      check_date
    )
  end
end
