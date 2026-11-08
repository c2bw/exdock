defmodule Exdock.Server.Jobs.Local.Registry do
  @moduledoc """
  Builds and runs server-local registry metadata refresh jobs.

  Request planning and remote fetching live in dedicated modules; this facade
  owns job construction, completion publication, and the stable public API.
  """

  require Logger
  alias Exdock.Server.{Jobs, State}
  alias Exdock.Server.Jobs.Local.Completion
  alias Exdock.Server.Jobs.Local.Registry.{Context, Fetcher, FetchReport, Plan}
  alias Exdock.Server.Jobs.{Detail, Runtime, Spec}
  alias Exdock.Server.Jobs.Payload.RegistryFetch
  alias Exdock.Server.State.Storage
  alias Exdock.Server.State.Storage.Containers

  @spec fetch_cluster(State.t()) :: Jobs.Detail.t() | nil
  def fetch_cluster(%State{tags: tags, cluster: %Storage.Cluster{storage: storage}}),
    do: build_detail(Containers.list(storage), tags, Plan.node_platforms(storage))

  @spec fetch_node(State.t(), String.t()) :: Jobs.Detail.t() | nil
  def fetch_node(%State{tags: tags, cluster: %Storage.Cluster{storage: storage}}, node)
      when is_binary(node),
      do: build_detail(Containers.list_node(storage, node), tags, Plan.node_platforms(storage))

  @spec build_detail(
          [Exdock.Domain.Container.t()],
          Storage.TagsInfo.t(),
          %{String.t() => String.t()}
        ) :: Jobs.Detail.t() | nil
  def build_detail(containers, %Storage.TagsInfo{} = tags_info, platforms_by_node)
      when is_list(containers) and is_map(platforms_by_node) do
    containers
    |> Plan.running_image_requests(platforms_by_node)
    |> detail_for_images(tags_info)
  end

  @spec running_image_requests(
          [Exdock.Domain.Container.t()],
          %{String.t() => String.t()}
        ) :: [%{tag: String.t(), platform: String.t()}]
  defdelegate running_image_requests(containers, platforms_by_node), to: Plan

  @doc false
  defdelegate collect_remote_report(stream), to: Fetcher, as: :collect_report

  @doc false
  defdelegate fetch_tag(image_tag, platform, previous_tag_info, job_id, fetch_fun, update_fun),
    to: Fetcher

  defp detail_for_images([], _tags_info), do: nil

  defp detail_for_images(image_requests, tags_info) do
    local =
      Spec.Local.new(fn job_id, runtime ->
        refresh_images(image_requests, tags_info, job_id, runtime)
      end)

    Detail.new(:registry_fetch, Spec.new(local, [], RegistryFetch.new(image_requests)))
  end

  defp refresh_images(image_requests, %Storage.TagsInfo{} = tags_info, job_id, %Runtime{} = runtime) do
    Logger.info("Fetching Registry for #{inspect(length(image_requests))} images")

    context = Context.new(update_publisher: &Jobs.job_update(&1, runtime.jobs))

    image_requests
    |> Fetcher.fetch(tags_info, job_id, context)
    |> complete_refresh(job_id, runtime)
  end

  @doc false
  @spec complete_refresh({:ok, FetchReport.t()}, String.t(), Runtime.t()) :: :ok
  def complete_refresh({:ok, %FetchReport{} = report}, job_id, %Runtime{} = runtime) do
    error = FetchReport.error(report)
    result = Jobs.Result.new(job_id, nil, :done, error)

    # Commit usable partial metadata before publishing the terminal failure.
    # A failed fetch must stop workflow continuations even when persistence succeeds.
    case Completion.publish(
           Storage.TagsInfo.Change.tags(report.tags),
           result,
           &Exdock.Runtime.Coordinator.commit_state_change(&1, runtime.coordinator),
           &Jobs.job_result(&1, runtime.jobs)
         ) do
      :ok when not is_nil(error) ->
        Logger.error("Registry fetch task incomplete: #{inspect(error)}")

      :ok ->
        Logger.info("Registry fetch task completed.")

      {:error, reason} ->
        Logger.error("Registry fetch task failed: #{inspect(reason)}")
    end
  end
end
