defmodule Exdock.ClientLib.Async.Batch do
  @moduledoc """
  Describes a bounded polling loop for data that is expensive or slow to fetch.

  `count` is the number of times the function may actually run. Calls to
  `run/2` also return the delay for the next tick, so the GenServer can poll on
  schedule without holding the process while waiting.
  """

  defstruct [
    :name,
    :id,
    :count,
    :interval,
    :function,
    :last_run,
    :generation
  ]

  @type t :: %__MODULE__{
          name: atom(),
          id: String.t(),
          count: integer(),
          interval: integer(),
          function: function(),
          generation: reference() | nil,
          last_run: DateTime.t() | nil
        }

  @spec new(atom(), String.t(), integer(), integer(), function()) :: t()
  def new(name, id, count, interval, function)
      when is_atom(name) and is_binary(id) and is_integer(count) and is_integer(interval) and
             is_function(function) and
             count > 0 and interval >= 0 do
    %__MODULE__{
      name: name,
      id: id,
      count: count,
      interval: interval,
      function: function,
      last_run: nil
    }
  end

  @spec run(t(), DateTime.t()) :: {t(), boolean(), non_neg_integer()}
  def run(%__MODULE__{last_run: nil, interval: interval, count: count} = batch, %DateTime{} = now) do
    # First execution happens immediately, then subsequent calls honor
    # `interval` relative to the previous real run.
    {%{batch | count: count - 1, last_run: now}, true, interval}
  end

  def run(%__MODULE__{last_run: last_run, interval: interval, count: count} = batch, %DateTime{} = now) do
    DateTime.diff(now, last_run, :millisecond)
    |> case do
      diff when diff >= interval ->
        {%{batch | count: count - 1, last_run: now}, true, interval}

      diff ->
        {batch, false, interval - diff}
    end
  end
end
