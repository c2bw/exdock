defmodule Exdock.Server.Jobs.Catalog do
  @moduledoc """
  Canonical capabilities for every runtime job name.

  Execution modules remain explicit at their protocol boundaries, while state
  routing, duplicate-work policy, and status registration derive their shared
  decisions from this catalog.
  """

  @type job_name ::
          :node_refresh
          | :registry_fetch
          | :releases_fetch
          | :container_recreate
          | :container_start
          | :container_stop
          | :container_restart
          | :container_logs
          | :image_delete
          | :image_pull

  @type client_result_handler :: :node_refresh | :container | nil
  @type status_adapter ::
          :node_refresh
          | :registry_fetch
          | :releases_fetch
          | :container_recreate
          | :container_action
          | :container_logs
          | :image_delete
          | :image_pull

  @type entry :: %{
          required(:client_result_handler) => client_result_handler(),
          required(:completion_log?) => boolean(),
          required(:failure_verb) => String.t() | nil,
          required(:linkable_remote_mutation?) => boolean(),
          required(:mirror_message?) => boolean(),
          required(:status_adapter) => status_adapter()
        }

  entry = fn status_adapter, overrides ->
    Map.merge(
      %{
        client_result_handler: nil,
        completion_log?: false,
        failure_verb: nil,
        linkable_remote_mutation?: false,
        mirror_message?: false,
        status_adapter: status_adapter
      },
      Map.new(overrides)
    )
  end

  @catalog %{
    node_refresh: entry.(:node_refresh, client_result_handler: :node_refresh, completion_log?: true),
    registry_fetch: entry.(:registry_fetch, []),
    releases_fetch: entry.(:releases_fetch, completion_log?: true),
    container_recreate:
      entry.(:container_recreate,
        client_result_handler: :container,
        failure_verb: "recreating container",
        linkable_remote_mutation?: true,
        mirror_message?: true
      ),
    container_start:
      entry.(:container_action,
        client_result_handler: :container,
        failure_verb: "starting container",
        linkable_remote_mutation?: true
      ),
    container_stop:
      entry.(:container_action,
        client_result_handler: :container,
        failure_verb: "stopping container",
        linkable_remote_mutation?: true
      ),
    container_restart:
      entry.(:container_action,
        client_result_handler: :container,
        failure_verb: "restarting container",
        linkable_remote_mutation?: true,
        mirror_message?: true
      ),
    container_logs: entry.(:container_logs, client_result_handler: :container),
    image_delete:
      entry.(:image_delete,
        client_result_handler: :container,
        failure_verb: "deleting image",
        linkable_remote_mutation?: true
      ),
    image_pull:
      entry.(:image_pull,
        client_result_handler: :container,
        failure_verb: "pulling image",
        linkable_remote_mutation?: true,
        mirror_message?: true
      )
  }

  @spec all() :: %{job_name() => entry()}
  def all, do: @catalog

  @spec names() :: [job_name()]
  def names, do: Map.keys(@catalog)

  @spec fetch!(job_name()) :: entry()
  def fetch!(job_name), do: Map.fetch!(@catalog, job_name)

  @spec client_result_handler(term()) :: client_result_handler()
  def client_result_handler(job_name) do
    case Map.fetch(@catalog, job_name) do
      {:ok, entry} -> entry.client_result_handler
      :error -> nil
    end
  end

  @spec linkable_remote_mutation?(term()) :: boolean()
  def linkable_remote_mutation?(job_name) do
    case Map.fetch(@catalog, job_name) do
      {:ok, entry} -> entry.linkable_remote_mutation?
      :error -> false
    end
  end

  @spec container_mutation_names() :: [job_name()]
  def container_mutation_names do
    for {job_name, %{failure_verb: failure_verb}} <- @catalog,
        is_binary(failure_verb),
        do: job_name
  end

  @spec failure_verb!(job_name()) :: String.t()
  def failure_verb!(job_name) do
    case fetch!(job_name).failure_verb do
      failure_verb when is_binary(failure_verb) -> failure_verb
      nil -> raise ArgumentError, "job has no failure verb: #{inspect(job_name)}"
    end
  end
end
