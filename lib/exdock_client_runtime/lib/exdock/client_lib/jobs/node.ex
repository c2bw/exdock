defmodule Exdock.ClientLib.Jobs.Node do
  @moduledoc """
  Executes node-wide Docker refresh jobs.
  """

  require Logger
  alias Exdock.ClientLib.Utils
  alias Exdock.ClientLib.Jobs.Context
  alias Exdock.Docker.Error

  @spec node_refresh(String.t(), keyword(), Context.t()) ::
          {:ok, {map(), map()}} | {:error, Error.t(), {map(), map()}}
  def node_refresh(_job_id, opts, %Context{} = context) do
    Logger.info("Refreshing Node -> fetching [Containers]")
    {engine, conn} = Context.connect(context)
    retrieve_resources = Keyword.get(opts, :retrieve_resources, false)

    with {:ok, containers} <-
           engine.list_containers(conn, retrieve_resources, status: :all),
         :ok <- log_container_result(containers),
         {:ok, images} <- fetch_images(engine, conn) do
      Logger.info("OK | Refreshed [containers, images]")
      {:ok, {containers, images}}
    else
      {:error, error} -> {:error, error, {%{ok: [], errored: []}, %{ok: [], errored: []}}}
    end
  end

  defp log_container_result(containers) do
    Enum.each(containers.errored, fn {error, container} ->
      Logger.error("Fetch Container [#{container.name}]: #{Utils.error_message(error)}")
    end)

    Logger.info("Fetched Containers [#{length(containers.ok)} successful,#{length(containers.errored)} errored]")

    :ok
  end

  defp fetch_images(engine, conn) do
    Logger.info("Refreshing Node -> fetching [Images]")

    case engine.list_images(conn) do
      {:ok, images} ->
        Enum.each(images.errored, fn {error, id} ->
          Logger.error("Fetch Image [#{inspect(id)}]: #{Utils.error_message(error)}")
        end)

        Logger.info("Fetched Images [#{length(images.ok)} successful,#{length(images.errored)} errored]")

        {:ok, images}

      {:error, error} ->
        {:error, error}
    end
  end
end
