defmodule Exdock.Server.Jobs.Local.Releases.Fetcher do
  @moduledoc """
  Concurrent provider request execution for repository release jobs.

  The fetcher owns request concurrency, per-request progress publication, and
  result summarization. State mutation and final job completion remain the
  responsibility of the releases facade.
  """

  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.TaskStream
  alias Exdock.Server.Jobs.Local.Releases.{Context, HTTPRequest}
  alias Exdock.Domain.Repository

  @type request_result ::
          {:ok, String.t(), [Repository.Release.t()]}
          | {:error, String.t(), term()}

  @type summary :: %{
          errors: [{:error, String.t(), term()}],
          releases: [Repository.Release.t()]
        }

  @spec fetch([HTTPRequest.t()], String.t()) ::
          {:ok, [request_result()]} | {:error, :timeout | {:task_exit, term()}}
  def fetch(requests, job_id) when is_list(requests) and is_binary(job_id) do
    fetch(requests, job_id, Context.default())
  end

  @doc """
  Fetches releases using explicit HTTP and progress collaborators.

  Production callers normally use `fetch/2`, which supplies
  `Context.default/0`.
  """
  @spec fetch([HTTPRequest.t()], String.t(), Context.t()) ::
          {:ok, [request_result()]} | {:error, :timeout | {:task_exit, term()}}
  def fetch(requests, job_id, %Context{} = context)
      when is_list(requests) and is_binary(job_id) do
    requests
    |> request_result_stream(job_id, context)
    |> TaskStream.collect()
    |> TaskStream.result()
    |> case do
      {:ok, results} -> {:ok, results}
      {:error, reason, _partial_results} -> {:error, reason}
    end
  end

  @spec summarize([request_result()]) :: summary()
  def summarize(results) when is_list(results) do
    {errors, ok_results} = Enum.split_with(results, &match?({:error, _url, _error}, &1))
    %{errors: errors, releases: Enum.flat_map(ok_results, &result_releases/1)}
  end

  defp request_result_stream(requests, job_id, %Context{} = context) do
    Task.async_stream(requests, &execute_request(&1, job_id, context),
      ordered: false,
      max_concurrency: context.max_concurrency,
      timeout: context.timeout,
      on_timeout: :kill_task
    )
  end

  defp execute_request(%HTTPRequest{} = request, job_id, %Context{} = context) do
    request
    |> then(&Context.execute_request(context, &1))
    |> tap(fn _result -> publish_progress(context, job_id, request) end)
  end

  defp publish_progress(
         %Context{} = context,
         job_id,
         %HTTPRequest{provider: provider, repo_name: repo_name}
       ) do
    update = Jobs.Update.new(job_id, nil, {provider, repo_name}, false)
    Context.publish_update(context, update)
  end

  defp result_releases({:ok, _url, releases}), do: releases
  defp result_releases({:error, _url, _error}), do: []
end
