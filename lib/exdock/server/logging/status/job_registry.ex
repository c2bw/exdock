defmodule Exdock.Server.Logging.Status.JobRegistry do
  @moduledoc """
  Canonical registry for status-dashboard job types.

  A job is registered once with its behaviour module and optional lifecycle
  capabilities. Dashboard initialization and all runtime callback lookup are
  derived from this registry.
  """

  alias Exdock.Server.Jobs.Catalog

  alias Exdock.Server.Logging.Status.{
    ContainerAction,
    ContainerLogs,
    ContainerRecreate,
    ImageDelete,
    ImagePull,
    NodeRefresh,
    RegistryFetch,
    ReleasesFetch
  }

  alias Exdock.Server.Logging.Status.JobAdapter
  alias Exdock.Server.Logging.Status.Lifecycle

  @adapter_modules %{
    node_refresh: NodeRefresh,
    registry_fetch: RegistryFetch,
    releases_fetch: ReleasesFetch,
    container_recreate: ContainerRecreate,
    container_action: ContainerAction,
    container_logs: ContainerLogs,
    image_delete: ImageDelete,
    image_pull: ImagePull
  }

  @registrations Map.new(Catalog.all(), fn {job_name, entry} ->
                   {job_name,
                    %JobAdapter{
                      module: Map.fetch!(@adapter_modules, entry.status_adapter),
                      completion_log?: entry.completion_log?,
                      mirror_message?: entry.mirror_message?
                    }}
                 end)

  @type job_name :: Catalog.job_name()

  @type registration :: JobAdapter.t()

  @spec all() :: %{job_name() => registration()}
  def all, do: @registrations

  @spec names() :: [job_name()]
  def names, do: Map.keys(@registrations)

  @spec initial_dash() :: %{job_name() => map()}
  def initial_dash, do: Map.new(@registrations, fn {job_name, _registration} -> {job_name, %{}} end)

  @spec fetch!(atom()) :: registration()
  def fetch!(job_name) when is_atom(job_name) do
    case Map.fetch(@registrations, job_name) do
      {:ok, registration} -> registration
      :error -> raise ArgumentError, "unknown status job: #{inspect(job_name)}"
    end
  end

  @spec module!(atom()) :: module()
  def module!(job_name), do: fetch!(job_name).module

  @spec mirror_message?(atom()) :: boolean()
  def mirror_message?(job_name), do: fetch!(job_name).mirror_message?

  @spec completion_log_options(struct(), Lifecycle.t()) :: keyword()
  def completion_log_options(status, %Lifecycle{job_name: job_name} = lifecycle) do
    job_name |> fetch!() |> JobAdapter.completion_log_options(status, lifecycle)
  end

  @spec update_effects(struct(), Lifecycle.t()) :: [Exdock.Server.Logging.Status.effect()]
  def update_effects(status, %Lifecycle{job_name: job_name} = lifecycle) do
    job_name |> fetch!() |> JobAdapter.update_effects(status, lifecycle)
  end

  @spec result_effects(struct(), Lifecycle.t()) :: [Exdock.Server.Logging.Status.effect()]
  def result_effects(status, %Lifecycle{job_name: job_name} = lifecycle) do
    job_name |> fetch!() |> JobAdapter.result_effects(status, lifecycle)
  end
end
