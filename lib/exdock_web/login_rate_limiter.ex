defmodule ExdockWeb.LoginRateLimiter do
  @moduledoc """
  In-memory rate limiter for password-verification attempts.

  Attempts are grouped by the resolved client IP. A successful login clears
  that source's window, while stale windows are periodically removed so the
  limiter does not retain inactive addresses indefinitely.
  """

  use GenServer

  @type key :: term()
  @type consume_result :: :ok | {:error, {:rate_limited, pos_integer()}}

  defstruct [:max_attempts, :window_ms, :clock, attempts: %{}]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    case name do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @doc """
  Consume one attempt for `key`.

  Returns the remaining wait in seconds when the current window is exhausted.
  """
  @spec consume(key(), GenServer.server()) :: consume_result()
  def consume(key, server \\ __MODULE__) do
    GenServer.call(server, {:consume, key})
  end

  @doc "Clear all recorded attempts for `key`."
  @spec reset(key(), GenServer.server()) :: :ok
  def reset(key, server \\ __MODULE__) do
    GenServer.call(server, {:reset, key})
  end

  @impl true
  def init(opts) do
    max_attempts = Keyword.fetch!(opts, :max_attempts)
    window_ms = Keyword.fetch!(opts, :window_ms)
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)

    true = is_integer(max_attempts) and max_attempts > 0
    true = is_integer(window_ms) and window_ms > 0
    true = is_function(clock, 0)

    schedule_cleanup(window_ms)

    {:ok, %__MODULE__{max_attempts: max_attempts, window_ms: window_ms, clock: clock}}
  end

  @impl true
  def handle_call({:consume, key}, _from, state) do
    now = state.clock.()

    case Map.get(state.attempts, key) do
      {count, started_at} when now - started_at < state.window_ms and count >= state.max_attempts ->
        retry_after = retry_after_seconds(started_at, now, state.window_ms)
        {:reply, {:error, {:rate_limited, retry_after}}, state}

      {count, started_at} when now - started_at < state.window_ms ->
        attempts = Map.put(state.attempts, key, {count + 1, started_at})
        {:reply, :ok, %{state | attempts: attempts}}

      _expired_or_missing ->
        attempts = Map.put(state.attempts, key, {1, now})
        {:reply, :ok, %{state | attempts: attempts}}
    end
  end

  def handle_call({:reset, key}, _from, state) do
    {:reply, :ok, %{state | attempts: Map.delete(state.attempts, key)}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = state.clock.()

    attempts =
      Map.reject(state.attempts, fn {_key, {_count, started_at}} ->
        now - started_at >= state.window_ms
      end)

    schedule_cleanup(state.window_ms)
    {:noreply, %{state | attempts: attempts}}
  end

  defp retry_after_seconds(started_at, now, window_ms) do
    remaining_ms = max(started_at + window_ms - now, 1)
    div(remaining_ms + 999, 1_000)
  end

  defp schedule_cleanup(window_ms) do
    _timer = Process.send_after(self(), :cleanup, window_ms)
    :ok
  end
end
