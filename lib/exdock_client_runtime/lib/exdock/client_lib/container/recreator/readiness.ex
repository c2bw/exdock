defmodule Exdock.ClientLib.Container.Recreator.Readiness do
  @moduledoc """
  Bounded verification before deleting the original container.

  Healthchecked replacements must become healthy. Other replacements must stay
  running for a short grace period. Each inspect is bounded by the remaining
  deadline, independently of the Docker client's longer request timeout.
  """

  @spec await((-> {:ok, term()} | {:error, term()}), keyword()) :: :ok | {:error, term()}
  def await(inspect_container, options \\ []) do
    if Keyword.get(options, :readiness, true) do
      timeout = Keyword.get(options, :readiness_timeout, 30_000)
      deadline = now() + timeout
      poll(inspect_container, options, deadline, nil)
    else
      :ok
    end
  end

  defp poll(inspect_container, options, deadline, stable) do
    case inspect_before(inspect_container, deadline) do
      {:ok, %{State: %{Status: "running"} = state}} ->
        verify_running(state, inspect_container, options, deadline, stable)

      {:ok, %{State: %{Status: status}}} when is_binary(status) ->
        {:error, :replacement_not_running}

      {:ok, _malformed} ->
        {:error, :malformed_response}

      {:error, _reason} = error ->
        error
    end
  end

  defp verify_running(state, inspect_container, options, deadline, stable) do
    case Map.get(state, :Health) do
      %{Status: "healthy"} -> :ok
      %{Status: "unhealthy"} -> {:error, :replacement_unhealthy}
      %{Status: "starting"} -> wait(inspect_container, options, deadline, nil)
      nil -> verify_stable(state, inspect_container, options, deadline, stable)
      _ -> {:error, :malformed_response}
    end
  end

  defp verify_stable(state, inspect_container, options, deadline, stable) do
    started_at = Map.get(state, :StartedAt)
    {since, _} = stable = stable_since(stable, started_at)

    if now() - since >= Keyword.get(options, :readiness_grace, 1_000),
      do: :ok,
      else: wait(inspect_container, options, deadline, stable)
  end

  defp stable_since({since, started_at}, started_at), do: {since, started_at}
  defp stable_since(_stable, started_at), do: {now(), started_at}

  defp inspect_before(inspect_container, deadline) do
    remaining = max(deadline - now(), 0)

    if remaining == 0 do
      {:error, :readiness_timeout}
    else
      task = Task.async(inspect_container)

      case Task.yield(task, remaining) || Task.shutdown(task, :brutal_kill) do
        {:ok, result} -> result
        _ -> {:error, :readiness_timeout}
      end
    end
  end

  defp wait(inspect_container, options, deadline, stable) do
    delay = min(Keyword.get(options, :readiness_interval, 250), max(deadline - now(), 0))

    receive do
    after
      delay -> poll(inspect_container, options, deadline, stable)
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end
