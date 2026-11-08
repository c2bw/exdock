defmodule Exdock.Server.Broadcast do
  @moduledoc """
  Batched PubSub broadcaster for server state updates.

  State domains push their latest view model here instead of broadcasting
  directly. The GenServer interprets the pure transition effects produced by
  `Exdock.Server.Broadcast.Policy`.
  """

  use GenServer
  require Logger

  alias Exdock.Events
  alias Exdock.ReadModel.Projections
  alias Exdock.Server.Broadcast.{BroadcastState, Policy}

  def start_link(args) do
    case Keyword.get(args, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, args)
      name -> GenServer.start_link(__MODULE__, args, name: name)
    end
  end

  @impl true
  def init(_opts) do
    {:ok, BroadcastState.new()}
  end

  @doc """
  Broadcast a typed message to all connected Phoenix views.

  Messages are sent to the `Exdock` topic. By default they are batched during a
  short refresh window; `force: true` flushes immediately. `delayed: true`
  stores only the latest message for a type until the delay expires.

  Options:

    * `:force` - flush the current immediate batch without waiting for the
      broadcast window.
    * `:delayed` - keep only the latest payload for this type until the delay
      window expires.
    * `:delay_ms` - override the delayed broadcast window.
  """
  @spec broadcast(atom(), any(), keyword()) :: :ok
  def broadcast(type, message, opts \\ []), do: broadcast(__MODULE__, type, message, opts)

  @doc false
  @spec broadcast(GenServer.server(), atom(), any(), keyword()) :: :ok
  def broadcast(server, type, message, opts) when is_list(opts),
    do: cast(server, {:broadcast, {type, message, opts}})

  @impl true
  def handle_cast({:broadcast, {type, message, opts}}, state) do
    transition =
      if known_broadcast_type?(type) do
        Policy.stage(state, type, {message, Keyword.get(opts, :revision)}, opts)
      else
        {state, []}
      end

    {:noreply, apply_transition(transition)}
  end

  @impl true
  def handle_cast({:cooldown}, state),
    do: {:noreply, state |> Policy.cooldown() |> apply_transition()}

  @impl true
  def handle_cast({:ready_to_broadcast}, state),
    do: {:noreply, state |> Policy.ready() |> apply_transition()}

  @impl true
  def handle_cast({:broadcast_delayed, type, generation}, state),
    do: {:noreply, state |> Policy.delayed_ready(type, generation) |> apply_transition()}

  @impl true
  def handle_info({:cooldown}, state), do: handle_scheduled_cast({:cooldown}, state)

  @impl true
  def handle_info({:ready_to_broadcast}, state),
    do: handle_scheduled_cast({:ready_to_broadcast}, state)

  @impl true
  def handle_info({:broadcast_delayed, type, generation}, state),
    do: handle_scheduled_cast({:broadcast_delayed, type, generation}, state)

  defp apply_transition({state, effects}) do
    Enum.each(effects, &run_effect/1)
    state
  end

  defp run_effect({:schedule, message, delay_ms}) do
    Process.send_after(self(), message, delay_ms)
    :ok
  end

  defp run_effect({:publish, payloads}) do
    Enum.each(payloads, fn {type, payload} ->
      publish_payload(type, payload)
    end)
  end

  @spec publish_payload(atom(), any()) :: :ok
  defp publish_payload(message_topic, {message, nil}),
    do:
      Events.publish(
        Projections.topic_for_source!(message_topic),
        %{source: message_topic, data: message}
      )

  defp publish_payload(message_topic, {message, revision}),
    do:
      Events.publish(
        Projections.topic_for_source!(message_topic),
        revision,
        %{source: message_topic, data: message}
      )

  @spec known_broadcast_type?(atom()) :: boolean()
  defp known_broadcast_type?(type) do
    valid = Projections.known_source?(type)
    if !valid, do: Logger.error("Unknown broadcast type: #{type}")
    valid
  end

  defp handle_scheduled_cast(message, state), do: handle_cast(message, state)

  defp cast(server, to_cast), do: GenServer.cast(server, to_cast)
end
