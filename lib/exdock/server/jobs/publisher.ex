defmodule Exdock.Server.Jobs.Publisher do
  @moduledoc """
  Publishes job lifecycle events to PubSub and the public operations stream.

  The dispatcher and effect interpreter share this boundary so event mapping
  remains independent of GenServer callbacks and job-state transitions.
  """

  @behaviour Exdock.Server.Jobs.PublisherBehaviour

  alias Exdock.Events
  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.Event
  alias Phoenix.PubSub

  @jobs_topic "jobs"

  @spec subscribe(atom()) :: :ok | {:error, term()}
  def subscribe(pubsub \\ Exdock.PubSub), do: PubSub.subscribe(pubsub, @jobs_topic, link: true)

  @spec subscribe_to_node_changes(atom()) :: :ok | {:error, term()}
  def subscribe_to_node_changes(pubsub \\ Exdock.PubSub),
    do: PubSub.subscribe(pubsub, "nodechange", link: true)

  @spec package_started(Jobs.Package.t() | term(), keyword()) :: :ok
  def package_started(job_format, opts \\ [])

  def package_started(%Jobs.Package{} = package, opts),
    do: publish(Event.package_started(package), opts)

  def package_started(_job_format, _opts), do: :ok

  @spec job_started(Jobs.Job.t(), keyword()) :: :ok
  def job_started(%Jobs.Job{} = job, opts \\ []),
    do: publish(Event.job_started(job), opts)

  @spec job_finished(Jobs.Info.t(), Jobs.Result.t(), keyword()) :: :ok
  def job_finished(%Jobs.Info{} = info, %Jobs.Result{} = result, opts \\ []),
    do: publish_job_event(info, :job_result, result, opts)

  @spec job_message(Jobs.Message.t(), keyword()) :: :ok
  def job_message(%Jobs.Message{} = message, opts \\ []),
    do: publish(Event.job_message(message), opts)

  @spec running_job_event(Jobs.State.t(), atom(), String.t(), term(), keyword()) :: :ok
  def running_job_event(%Jobs.State{} = state, event, id, event_data, opts \\ [])
      when is_atom(event) and is_binary(id) do
    state
    |> Jobs.State.get_job_info(id)
    |> publish_job_event(event, event_data, opts)
  end

  @spec package_finished(String.t(), term(), keyword()) :: :ok
  def package_finished(id, completion_error, opts \\ []) when is_binary(id) do
    :ok = publish(Event.package_finished(id, completion_error), opts)
    events(opts).operation_finished(id, :package, completion_error)
  end

  @spec terminal_operation(Jobs.Info.t() | nil, Jobs.State.t(), Jobs.Result.t(), keyword()) :: :ok
  def terminal_operation(info, state, result, opts \\ [])

  def terminal_operation(nil, %Jobs.State{}, %Jobs.Result{}, _opts), do: :ok

  def terminal_operation(
        %Jobs.Info{name: name},
        %Jobs.State{} = state,
        %Jobs.Result{id: id} = result,
        opts
      ) do
    if Jobs.State.get_job_info(state, id) == nil do
      events(opts).operation_finished(id, name, result)
    else
      :ok
    end
  end

  defp publish_job_event(nil, _event, _event_data, _opts), do: :ok

  defp publish_job_event(%Jobs.Info{} = info, event, event_data, opts) when is_atom(event) do
    with {:ok, job_event} <- build_job_event(event, info, event_data),
         :ok <- publish(job_event, opts) do
      events(opts).publish(:activity, %{kind: event, info: info, data: event_data})
    end
  end

  defp build_job_event(:job_result, %Jobs.Info{} = info, %Jobs.Result{} = result),
    do: {:ok, Event.job_finished(info, result)}

  defp build_job_event(:job_update, %Jobs.Info{} = info, %Jobs.Update{} = update),
    do: {:ok, Event.job_updated(info, update)}

  defp build_job_event(event, _info, _event_data),
    do: {:error, {:unsupported_job_event, event}}

  defp publish(%Event{} = event, opts),
    do: PubSub.broadcast(Keyword.get(opts, :pubsub, Exdock.PubSub), @jobs_topic, event)

  defp events(opts), do: Keyword.get(opts, :events, Events)
end
