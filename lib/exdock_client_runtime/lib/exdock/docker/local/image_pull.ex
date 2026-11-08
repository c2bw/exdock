defmodule Exdock.Docker.Local.ImagePull do
  @moduledoc """
  Supervises one streamed Docker image pull.

  The transport request runs under the connection task supervisor while a
  consumer process translates transport chunks into semantic progress and
  completion messages.
  """

  alias Exdock.Docker.Local.Helpers.ImagePullConsumer
  alias Exdock.Docker.Local.ImagePull.Session
  alias Exdock.Docker.Local.Image.PullTransport.Tesla, as: TeslaTransport
  alias Exdock.Docker.Error

  @default_timeout Exdock.Protocol.ExecutionBudget.request_timeout()
  @default_task_supervisor Exdock.Client.Connection.TaskSupervisor

  @spec run(term(), String.t(), atom() | nil, String.t() | nil, keyword()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def run(conn, image_tag, job_name, job_id, opts \\ [])
      when is_binary(image_tag) and is_list(opts) do
    consumer = Keyword.get(opts, :consumer, ImagePullConsumer)
    transport = Keyword.get(opts, :transport, TeslaTransport)
    task_supervisor = Keyword.get(opts, :task_supervisor, @default_task_supervisor)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    caller = self()
    consumer_name = {:via, Registry, {Exdock.AgentRegistry, {:image_pull_handler, image_tag}}}

    case consumer.start_link({consumer_name, {caller, job_name, job_id}}) do
      {:error, {:already_started, _pid}} ->
        {:error, Error.new(:image_pull, :already_in_progress, message: "Image pull already in progress")}

      {:ok, consumer_pid} ->
        start_request(
          task_supervisor,
          transport,
          conn,
          image_tag,
          consumer_pid,
          timeout
        )
    end
  end

  defp start_request(task_supervisor, transport, conn, image_tag, consumer_pid, timeout) do
    # async_nolink installs the monitor before the request can exit. Monitoring
    # a start_child pid afterwards can lose a fast failure as :noproc.
    task =
      Task.Supervisor.async_nolink(task_supervisor, fn ->
        result = transport.stream(conn, image_tag, consumer_pid)
        send(consumer_pid, {:stream_request_result, result})
      end)

    image_tag
    |> Session.new(consumer_pid, task_supervisor, task, timeout)
    |> Session.await()
  rescue
    exception ->
      stop_consumer(consumer_pid)
      {:error, Error.new({:image_pull, :request_start}, exception, message: "Unable to start image pull request")}
  catch
    :exit, reason ->
      stop_consumer(consumer_pid)
      {:error, Error.new({:image_pull, :request_start}, reason, message: "Unable to start image pull request")}
  end

  defp stop_consumer(consumer_pid) do
    GenServer.stop(consumer_pid, :normal)
  catch
    :exit, _reason -> :ok
  end
end
