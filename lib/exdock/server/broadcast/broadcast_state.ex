defmodule Exdock.Server.Broadcast.BroadcastState do
  @moduledoc """
  Tracks staged immediate and delayed payloads while batching broadcast updates.
  """

  @typedoc """
  Maps a broadcast type to the last staged payload for that type.
  """
  @type payload_by_type :: %{atom() => any()}
  @type generation_by_type :: %{atom() => pos_integer()}

  defstruct broadcast_window_open: true,
            immediate_flush_needed: false,
            staged_immediate_buckets: %{},
            staged_delayed_buckets: %{},
            delayed_generations: %{}

  @type t :: %__MODULE__{
          broadcast_window_open: boolean(),
          immediate_flush_needed: boolean(),
          staged_immediate_buckets: payload_by_type(),
          staged_delayed_buckets: payload_by_type(),
          delayed_generations: generation_by_type()
        }

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Stage a latest immediate payload for a broadcast type.

  Immediate payloads enter the flush batch and supersede any pending delayed
  payload for the same type, so old delayed data cannot replay later.
  """
  @spec put_immediate_payload(t(), atom(), any()) :: t()
  def put_immediate_payload(state, type, message) do
    state
    |> clear_staged_delayed_payload(type)
    |> stage_immediate_payload(type, message)
    |> mark_immediate_flush_needed()
  end

  @doc """
  Stage a latest delayed payload for a broadcast type.

  Delayed staging is last-write-wins per type until the timer re-enters the
  payload through the immediate path.
  """
  @spec put_delayed_payload(t(), atom(), any()) :: t()
  def put_delayed_payload(state, type, message) do
    stage_delayed_payload(state, type, message)
  end

  @doc """
  Starts a new delayed window and returns its generation token.

  Generations remain in state after a payload is cleared so a timer from an
  earlier window cannot match a later payload for the same broadcast type.
  """
  @spec start_delayed_payload(t(), atom(), any()) :: {t(), pos_integer()}
  def start_delayed_payload(%__MODULE__{delayed_generations: generations} = state, type, message) do
    generation = Map.get(generations, type, 0) + 1

    state = %{
      state
      | staged_delayed_buckets: Map.put(state.staged_delayed_buckets, type, message),
        delayed_generations: Map.put(generations, type, generation)
    }

    {state, generation}
  end

  @spec delayed_payload_active?(t(), atom()) :: boolean()
  def delayed_payload_active?(state, type), do: Map.has_key?(state.staged_delayed_buckets, type)

  @spec fetch_delayed_payload(t(), atom(), pos_integer()) :: {:ok, any()} | :error
  def fetch_delayed_payload(state, type, generation) do
    case {Map.fetch(state.staged_delayed_buckets, type), Map.fetch(state.delayed_generations, type)} do
      {{:ok, payload}, {:ok, ^generation}} -> {:ok, payload}
      _ -> :error
    end
  end

  @spec delete_delayed_payload(t(), atom()) :: t()
  def delete_delayed_payload(state, type), do: clear_staged_delayed_payload(state, type)

  @spec immediate_payloads(t()) :: payload_by_type()
  def immediate_payloads(state), do: state.staged_immediate_buckets

  @spec close_broadcast_window(t()) :: t()
  def close_broadcast_window(state), do: %{state | broadcast_window_open: false}

  @spec open_broadcast_window(t()) :: t()
  def open_broadcast_window(state), do: %{state | broadcast_window_open: true}

  @spec flush_immediate_buckets(t()) :: t()
  def flush_immediate_buckets(state) do
    %{state | staged_immediate_buckets: %{}, immediate_flush_needed: false}
  end

  defp stage_immediate_payload(%__MODULE__{staged_immediate_buckets: payloads} = state, type, message) do
    %{state | staged_immediate_buckets: Map.put(payloads, type, message)}
  end

  defp stage_delayed_payload(%__MODULE__{staged_delayed_buckets: payloads} = state, type, message) do
    %{state | staged_delayed_buckets: Map.put(payloads, type, message)}
  end

  defp clear_staged_delayed_payload(%__MODULE__{staged_delayed_buckets: payloads} = state, type) do
    %{state | staged_delayed_buckets: Map.delete(payloads, type)}
  end

  defp mark_immediate_flush_needed(%__MODULE__{} = state), do: %{state | immediate_flush_needed: true}
end
