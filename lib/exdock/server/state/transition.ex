defmodule Exdock.Server.State.Transition do
  @moduledoc """
  Commits reducer results through the configured state-effect interpreter.

  Reducers return either an updated state with effects or a tagged error that
  retains the prior state. This module is the single place that turns those
  values into committed runtime state.
  """

  alias Exdock.Server.State
  alias Exdock.Server.State.Change.Outcome
  alias Exdock.Server.State.EffectExecutor
  alias Exdock.Server.State.Effects

  require Logger

  @type result :: Outcome.t() | {:error, term(), State.t()}

  @spec commit(result(), keyword()) ::
          {:ok, State.t()} | {:error, term(), State.t()}
  def commit(result, opts \\ [])

  def commit(%Outcome{state: %State{} = state, effects: effects}, opts) when is_list(effects) do
    :ok = run_effects(state, effects, opts)
    {:ok, state}
  end

  def commit({:error, reason, %State{} = state}, opts) when is_list(opts) do
    log_error(reason, opts)
    {:error, reason, state}
  end

  @spec commit_with_result(result(), keyword()) ::
          {:ok, State.t(), map()} | {:error, term(), State.t()}
  def commit_with_result(result, opts \\ [])

  def commit_with_result(
        %Outcome{state: %State{} = state, effects: effects, operation_result: operation_result},
        opts
      )
      when is_list(effects) do
    :ok = run_effects(state, effects, opts)
    {:ok, state, operation_result || %{status: :completed}}
  end

  def commit_with_result({:error, reason, %State{} = state}, opts) when is_list(opts) do
    log_error(reason, opts)
    {:error, reason, state}
  end

  @spec commit_pair({State.t(), [Effects.effect()]}, keyword()) :: State.t()
  def commit_pair(result, opts \\ [])

  def commit_pair({%State{} = state, effects}, opts) when is_list(effects) and is_list(opts) do
    :ok = run_effects(state, effects, opts)
    state
  end

  defp run_effects(state, effects, opts) do
    case Keyword.fetch(opts, :effect_runner) do
      {:ok, runner} -> EffectExecutor.run(state, effects, runner)
      :error -> EffectExecutor.run(state, effects)
    end
  end

  defp log_error(reason, opts) do
    if Keyword.get(opts, :log_error, false) do
      Logger.error("#{Keyword.get(opts, :error_prefix, "State transition rejected")}: #{inspect(reason)}")
    end
  end
end
