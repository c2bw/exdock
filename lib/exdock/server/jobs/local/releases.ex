defmodule Exdock.Server.Jobs.Local.Releases do
  @moduledoc """
  Builds server-local repository release fetch jobs.

  `Plan` selects repositories, `Fetcher` executes provider requests, and this
  facade owns job construction plus completion publication.
  """

  require Logger

  alias Exdock.Runtime.Coordinator
  alias Exdock.Server.Jobs.Local.Completion
  alias Exdock.Server.Jobs.Local.Releases.{Fetcher, HTTPRequest, Plan}
  alias Exdock.Server.Jobs.{Detail, Runtime, Spec}
  alias Exdock.Server.Jobs.Local.Releases.Context
  alias Exdock.Server.Jobs.Payload.ReleasesFetch
  alias Exdock.Server.State
  alias Exdock.Server.State.Storage
  alias Exdock.Server.State.Storage.Repositories
  alias Exdock.Domain
  alias Exdock.Domain.Repository.Metadata

  def providers, do: HTTPRequest.providers()

  @doc """
  Fetch releases for all repositories in the cluster.

  `filter` contains page states used to restrict the refreshed repositories.
  """
  @spec fetch_cluster(State.t(), [Metadata.page_state()]) :: Detail.t() | nil
  def fetch_cluster(
        %State{repositories: repositories, cluster: %Storage.Cluster{storage: storage}} = state,
        filter
      )
      when is_list(filter) do
    urls =
      repositories
      |> Repositories.list(Storage.Images.repositories_urls(storage))
      |> Repositories.filter(filter)
      |> Enum.map(& &1.url)

    fetch_repositories(state, urls)
  end

  @doc """
  Fetch releases for a list of repository URLs.
  """
  @spec fetch_repositories(State.t(), [String.t()]) :: Detail.t() | nil
  def fetch_repositories(%State{repositories: repositories}, urls) when is_list(urls) do
    repos = Repositories.list(repositories, urls)
    releases_snapshot = Repositories.releases_of(repos)
    build_detail(repos, releases_snapshot)
  end

  @spec build_detail(
          [Domain.Repository.t()],
          [Domain.Repository.Release.t()]
        ) :: Detail.t() | nil
  def build_detail(repositories, releases_snapshot)
      when is_list(repositories) and is_list(releases_snapshot) do
    plan = Plan.build(repositories)
    report_unsupported_repositories(plan)
    detail_from_plan(plan, releases_snapshot)
  end

  @doc false
  defdelegate summarize_results(results), to: Fetcher, as: :summarize

  defp report_unsupported_repositories(plan) do
    results = Plan.unsupported_results(plan)
    Coordinator.state_change(Storage.Repositories.Change.releases(results))

    Enum.each(results, fn {:error, url, :unsupported} ->
      Logger.warning("Repository provider is not supported: #{inspect(url)}")
    end)
  end

  defp detail_from_plan(%{supported_urls: []}, _releases_snapshot), do: nil

  defp detail_from_plan(%{supported_urls: supported_urls}, releases_snapshot) do
    requests = Enum.map(supported_urls, &HTTPRequest.new/1)
    data = ReleasesFetch.new(request_labels(requests), releases_snapshot)
    local = Spec.Local.new(fn job_id, runtime -> execute_requests(requests, job_id, runtime) end)
    Detail.new(:releases_fetch, Spec.new(local, [], data))
  end

  defp request_labels(requests) do
    Enum.map(requests, fn %HTTPRequest{provider: provider, repo_name: repo_name} ->
      {provider, repo_name}
    end)
  end

  defp execute_requests(requests, job_id, %Runtime{} = runtime) do
    Logger.info("Fetching Releases from #{length(requests)} repositories")

    context = Context.new(update_publisher: &Exdock.Server.Jobs.job_update(&1, runtime.jobs))
    outcome = Fetcher.fetch(requests, job_id, context)

    case Completion.finish(
           job_id,
           outcome,
           &release_completion/1,
           &Coordinator.commit_state_change(&1, runtime.coordinator),
           &Exdock.Server.Jobs.job_result(&1, runtime.jobs)
         ) do
      :ok ->
        Logger.info("Releases fetch task completed.")

      {:error, reason} ->
        Logger.error("Releases fetch task failed: #{inspect(reason)}")
    end
  end

  defp release_completion(results) do
    %{errors: errors, releases: releases} = Fetcher.summarize(results)
    log_request_errors(errors)

    {Storage.Repositories.Change.releases(results), {:done, releases}}
  end

  defp log_request_errors(errors) do
    Enum.each(errors, fn {:error, url, error} ->
      Logger.warning("Repository: failed to fetch releases [#{url}]: #{inspect(error)}")
    end)
  end
end
