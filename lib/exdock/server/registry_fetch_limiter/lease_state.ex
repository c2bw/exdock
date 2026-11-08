defmodule Exdock.Server.RegistryFetchLimiter.LeaseState do
  @moduledoc """
  Pure lease and FIFO-waiter transitions for registry fetch limiting.

  Process monitoring and GenServer replies are represented as effects so the
  owning process can execute them after the deterministic state transition.
  """

  @type endpoint :: {String.t(), String.t()}

  alias Exdock.Server.RegistryFetchLimiter.LeaseState.{Bucket, Owner, Waiter}

  defstruct buckets: %{}, monitors: %{}

  @type monitor_owner :: {:owner, endpoint(), reference()} | {:waiting, endpoint()}

  @type t :: %__MODULE__{
          buckets: %{optional(endpoint()) => Bucket.t()},
          monitors: %{
            optional(reference()) => monitor_owner()
          }
        }

  @type effect ::
          {:demonitor, reference()}
          | {:reply, GenServer.from(), reference()}

  @type acquire_result ::
          {:granted, reference(), t()}
          | {:queued, t()}

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec acquire(t(), endpoint(), Waiter.t(), pos_integer()) :: acquire_result()
  def acquire(%__MODULE__{} = state, endpoint, %Waiter{} = waiter, max_concurrency)
      when is_integer(max_concurrency) and max_concurrency > 0 do
    bucket = Map.get(state.buckets, endpoint, Bucket.new())

    if map_size(bucket.owners) < max_concurrency do
      {lease, state} = grant(state, endpoint, waiter)
      {:granted, lease, state}
    else
      bucket = %{bucket | waiting: :queue.in(waiter, bucket.waiting)}

      state =
        state
        |> put_bucket(endpoint, bucket)
        |> put_monitor(waiter.monitor, {:waiting, endpoint})

      {:queued, state}
    end
  end

  @spec release(t(), endpoint(), reference(), pos_integer()) :: {t(), [effect()]}
  def release(%__MODULE__{} = state, endpoint, lease, max_concurrency) do
    release(state, endpoint, lease, max_concurrency, demonitor?: true)
  end

  @spec monitor_down(t(), reference(), pos_integer()) :: {t(), [effect()]}
  def monitor_down(%__MODULE__{} = state, monitor, max_concurrency) do
    case Map.get(state.monitors, monitor) do
      {:owner, endpoint, lease} ->
        release(state, endpoint, lease, max_concurrency, demonitor?: false)

      {:waiting, endpoint} ->
        {remove_waiter(state, endpoint, monitor), []}

      nil ->
        {state, []}
    end
  end

  defp release(state, endpoint, lease, max_concurrency, opts) do
    with %Bucket{owners: owners} = bucket <- Map.get(state.buckets, endpoint),
         %Owner{lease: ^lease} = owner <- Map.get(owners, lease) do
      bucket = %{bucket | owners: Map.delete(bucket.owners, lease)}

      state =
        state
        |> delete_monitor(owner.monitor)
        |> put_bucket(endpoint, bucket)

      effects =
        if Keyword.fetch!(opts, :demonitor?),
          do: [{:demonitor, owner.monitor}],
          else: []

      {state, promotion_effects} =
        promote_waiters(state, endpoint, max_concurrency)

      {state, effects ++ promotion_effects}
    else
      _missing_or_stale_lease -> {state, []}
    end
  end

  defp promote_waiters(state, endpoint, max_concurrency) do
    %Bucket{} = bucket = Map.fetch!(state.buckets, endpoint)

    cond do
      map_size(bucket.owners) < max_concurrency and
          not :queue.is_empty(bucket.waiting) ->
        {{:value, waiter}, remaining} = :queue.out(bucket.waiting)
        {lease, state} = grant(state, endpoint, waiter, remaining)

        {state, effects} =
          promote_waiters(state, endpoint, max_concurrency)

        {state, [{:reply, waiter.from, lease} | effects]}

      map_size(bucket.owners) == 0 ->
        {delete_bucket(state, endpoint), []}

      true ->
        {state, []}
    end
  end

  defp grant(%__MODULE__{} = state, endpoint, %Waiter{} = waiter, waiting \\ nil) do
    lease = make_ref()
    owner = %Owner{pid: waiter.pid, lease: lease, monitor: waiter.monitor}
    bucket = Map.get(state.buckets, endpoint, Bucket.new())
    waiting = waiting || bucket.waiting

    bucket = %{
      bucket
      | owners: Map.put(bucket.owners, lease, owner),
        waiting: waiting
    }

    state =
      state
      |> put_bucket(endpoint, bucket)
      |> put_monitor(waiter.monitor, {:owner, endpoint, lease})

    {lease, state}
  end

  defp remove_waiter(state, endpoint, monitor) do
    state = delete_monitor(state, monitor)

    %{state | buckets: update_waiting_queue(state.buckets, endpoint, monitor)}
  end

  defp update_waiting_queue(buckets, endpoint, monitor) do
    Map.update!(buckets, endpoint, fn %Bucket{} = bucket ->
      waiting =
        bucket.waiting
        |> :queue.to_list()
        |> Enum.reject(&(&1.monitor == monitor))
        |> :queue.from_list()

      %{bucket | waiting: waiting}
    end)
  end

  defp put_bucket(%__MODULE__{} = state, endpoint, %Bucket{} = bucket),
    do: %{state | buckets: Map.put(state.buckets, endpoint, bucket)}

  defp delete_bucket(%__MODULE__{} = state, endpoint),
    do: %{state | buckets: Map.delete(state.buckets, endpoint)}

  defp put_monitor(%__MODULE__{} = state, monitor, owner),
    do: %{state | monitors: Map.put(state.monitors, monitor, owner)}

  defp delete_monitor(%__MODULE__{} = state, monitor),
    do: %{state | monitors: Map.delete(state.monitors, monitor)}
end
