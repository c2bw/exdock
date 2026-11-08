defmodule Exdock.ClientLib.Jobs.Container do
  @moduledoc """
  Executes container-scoped Docker jobs.
  """

  require Logger

  alias Exdock.ClientLib, as: Client
  alias Exdock.ClientLib.Utils
  alias Exdock.ClientLib.Jobs.{ActionRunner, Context}
  alias Exdock.Docker.Error
  alias Exdock.Protocol.Messages

  @spec container_recreate(String.t(), String.t(), boolean(), Context.t()) ::
          {:ok, String.t() | map()} | {:error, Error.t(), String.t()}
  def container_recreate(job_id, id, pull_image, %Context{} = context) do
    Logger.info("Recreating container [#{id}]")
    {engine, conn} = Context.connect(context)

    with :ok <- maybe_pull_image(engine, conn, job_id, id, pull_image),
         {:ok, recreated} <- engine.recreate_container(conn, id, :container_recreate, job_id) do
      recreation_result(id, recreated)
    else
      {:error, {:pull, error}} ->
        Logger.error("Recreate container [#{id}]: failed to pull image: #{Utils.error_message(error)}")

        {:error, error, id}

      {:error, error} ->
        Logger.error("Recreate container [#{id}]: #{Utils.error_message(error)}")
        {:error, error, id}
    end
  end

  @spec container_start(String.t(), String.t(), Context.t()) ::
          {:ok, String.t()} | {:error, Error.t(), String.t()}
  def container_start(_job_id, id, %Context{} = context) do
    ActionRunner.run(
      "Starting",
      "Started",
      "Start",
      "container",
      id,
      fn engine, conn ->
        engine.start_container(conn, id)
      end,
      context
    )
  end

  @spec container_stop(String.t(), String.t(), Context.t()) ::
          {:ok, String.t()} | {:error, Error.t(), String.t()}
  def container_stop(_job_id, id, %Context{} = context) do
    ActionRunner.run(
      "Stopping",
      "Stopped",
      "Stop",
      "container",
      id,
      fn engine, conn ->
        engine.stop_container(conn, id)
      end,
      context
    )
  end

  @spec container_restart(String.t(), String.t(), Context.t()) ::
          {:ok, String.t()} | {:error, Error.t(), String.t()}
  def container_restart(job_id, id, %Context{} = context) do
    Logger.info("Restarting container [#{id}]")
    {engine, conn} = Context.connect(context)

    publish_restart_progress(job_id, "restarting")

    with {:ok, _response} <- engine.restart_container(conn, id) do
      Logger.info("OK | Restarted container [#{id}]")
      {:ok, id}
    else
      {:error, error} ->
        Logger.error("Restart container [#{id}]: #{Utils.error_message(error)}")
        {:error, error, id}
    end
  end

  @spec container_logs(String.t(), String.t(), keyword(), Context.t()) ::
          {:ok, {String.t(), [String.t()]}} | {:error, Error.t(), {String.t(), []}}
  def container_logs(_job_id, id, opts, %Context{} = context) do
    {engine, conn} = Context.connect(context)

    opts =
      opts
      |> Keyword.put_new(:stdout, true)
      |> Keyword.put_new(:stderr, true)
      |> Keyword.put_new(:tail, 50)

    case engine.container_logs(conn, id, opts) do
      {:ok, response} -> {:ok, {id, response}}
      {:error, error} -> {:error, error, {id, []}}
    end
  end

  @spec container_resources(String.t(), String.t(), Context.t()) ::
          {:ok, {String.t(), term()}} | {:error, Error.t(), {String.t(), %{}}}
  def container_resources(_job_id, id, %Context{} = context) do
    {engine, conn} = Context.connect(context)

    case engine.container_resources(conn, id) do
      {:ok, response} -> {:ok, {id, response}}
      {:error, error} -> {:error, error, {id, %{}}}
    end
  end

  defp recreation_result(id, %{id: new_id, warning: warning}) do
    Logger.info("OK | Recreated container [#{id}] as [#{new_id}] with cleanup warning")
    {:ok, %{"container" => id, "warning" => warning}}
  end

  defp recreation_result(id, new_id) when is_binary(new_id) do
    Logger.info("OK | Recreated container [#{id}] as [#{new_id}]")
    {:ok, id}
  end

  defp maybe_pull_image(_engine, _conn, _job_id, _id, false), do: :ok

  defp maybe_pull_image(engine, conn, job_id, id, true) do
    with {:ok, %{image_tag: tag}} <- engine.container_image_info(conn, id),
         {:ok, _response} <-
           engine.pull_image(conn, tag, true, :container_recreate, job_id) do
      Logger.info("OK | [#{id}] -> pulled image [#{tag}]")
      :ok
    else
      {:error, error} -> {:error, {:pull, error}}
    end
  end

  defp publish_restart_progress(nil, _message), do: :ok

  defp publish_restart_progress(job_id, message) do
    Client.send_job_update(Messages.Update.new(job_id, :container_restart, message))
  end
end
