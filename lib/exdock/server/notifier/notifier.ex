defmodule Exdock.Server.Notifier do
  @moduledoc """
  Optional notification bridge backed by the configured Loki logger handler.

  Domain code calls the public notify helpers with structured text. When the
  notifier is enabled, those messages are emitted through Logger with metadata
  that the configured Loki handler can route. When no Loki URL is configured,
  the helpers become no-ops.
  """

  use GenServer
  require Logger
  alias Exdock.Server.Jobs
  alias Exdock.Server.Notifier.{Handler, Policy}
  alias Exdock.Domain.TagInfo
  alias Exdock.Domain.Repository

  @disabled :disabled
  @enabled :enabled

  defstruct status: @disabled,
            url: nil,
            handler: Handler

  def start_link(args) when is_list(args) do
    {name, init_args} = Keyword.pop(args, :name, __MODULE__)
    options = if is_nil(name), do: [], else: [name: name]
    GenServer.start_link(__MODULE__, init_args, options)
  end

  @impl true
  def init(args) do
    Process.flag(:trap_exit, true)

    # Job failures arrive through backend PubSub; container/repository/image
    # notifications are explicit calls from storage transitions.
    with :ok <- maybe_subscribe_to_job_events(args),
         {:ok, state} <- initial_state(args) do
      {:ok, state, {:continue, :verify_notifier}}
    else
      {:error, error} -> {:stop, error}
      {:stop, error} -> {:stop, error}
    end
  end

  defp maybe_subscribe_to_job_events(args) do
    if Keyword.get(args, :subscribe?, true),
      do: Jobs.subscribe(Keyword.get(args, :pubsub, Exdock.PubSub)),
      else: :ok
  end

  defp initial_state(args) do
    # Missing Loki URL keeps the notifier intentionally disabled but still
    # fully booted so call sites can remain unconditional.
    logger_handlers =
      Keyword.get_lazy(args, :logger_handlers, fn -> Application.get_env(:exdock, :logger, []) end)

    handler = Keyword.get(args, :handler, Handler)
    {status, url, effects} = logger_handlers |> handler.configured_url() |> Policy.initialize()
    state = %__MODULE__{status: status, url: url, handler: handler}

    case run_effects(effects, state) do
      :ok -> {:ok, state}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:verify_notifier, %{status: @disabled} = state) do
    :ok = state.status |> Policy.continued(state.url) |> run_effects(state)
    {:noreply, state}
  end

  def handle_continue(:verify_notifier, %{status: @enabled, url: url} = state) do
    :ok = state.status |> Policy.continued(url) |> run_effects(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(%Jobs.Event{} = event, state) do
    :ok = state.status |> Policy.job_event(event) |> run_effects(state)
    {:noreply, state}
  end

  def handle_info({:EXIT, _pid, reason}, state) do
    {:stop, reason, state}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    state.status
    |> Policy.terminate(reason)
    |> run_effects(state)
  end

  @impl true
  def handle_call(:status, _from, state), do: {:reply, state.status, state}

  def notify_container_status(node, name, priority, old, new, server \\ __MODULE__),
    do:
      cast_notification(
        :container_status,
        %{
          node: node,
          name: name,
          priority: priority,
          old: old,
          new: new
        },
        server
      )

  def notify_repository_release(%Repository.Release{} = release, server \\ __MODULE__),
    do: cast_notification(:repository_release, release, server)

  def notify_image_tag(%TagInfo{} = tag_info, server \\ __MODULE__),
    do: cast_notification(:image_tag, tag_info, server)

  @impl true
  def handle_cast({:notify, type, payload}, state) do
    :ok = state.status |> Policy.notification(type, payload) |> run_effects(state)
    {:noreply, state}
  end

  @doc """
  Return whether notification emission is currently enabled.

  Callers use this instead of reaching into the GenServer protocol directly.
  When the notifier process is absent or shutting down, status resolves to
  disabled so notification helpers remain safe no-ops.
  """
  @spec status(GenServer.server()) :: :enabled | :disabled
  def status(server \\ __MODULE__) do
    case GenServer.whereis(server) do
      nil -> @disabled
      pid when pid == self() -> @disabled
      _pid -> call_status(server)
    end
  end

  def logger_filter(%{meta: %{caller: :notifier}} = _log_event, _opts), do: :ignore
  def logger_filter(_log_event, _opts), do: :stop

  defp cast_notification(type, payload, server) do
    if pid = GenServer.whereis(server) do
      GenServer.cast(pid, {:notify, type, payload})
    end

    :ok
  end

  defp log_notification(level, type, msg) when level in [:info, :error] and is_binary(msg) do
    Logger.log(level, msg, caller: :notifier, Exdock_type: type)
    :ok
  end

  defp call_status(server) do
    GenServer.call(server, :status)
  catch
    :exit, _reason -> @disabled
  end

  defp run_effects(effects, state) do
    Exdock.Result.each(effects, &run_effect(&1, state))
  end

  defp run_effect(:configure_handler, state), do: state.handler.configure()
  defp run_effect(:remove_handler, state), do: state.handler.remove()

  defp run_effect({:verify_connectivity, url}, state),
    do: state.handler.verify_connectivity(url)

  defp run_effect({:system_log, level, message}, _state) do
    Logger.log(level, message)
    :ok
  end

  defp run_effect({:notification_log, level, type, message}, _state),
    do: log_notification(level, type, message)
end
