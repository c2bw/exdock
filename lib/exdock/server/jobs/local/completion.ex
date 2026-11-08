defmodule Exdock.Server.Jobs.Local.Completion do
  @moduledoc false

  alias Exdock.Runtime.Mutation
  alias Exdock.Runtime.Coordinator
  alias Exdock.Server.Jobs

  @type commit_result :: :ok | {:error, term()}
  @type outcome(value) :: {:ok, value} | {:error, term()}

  @spec finish(String.t(), outcome(term()), (term() -> {Mutation.t(), term()})) :: commit_result()
  def finish(job_id, outcome, on_success)
      when is_binary(job_id) and is_function(on_success, 1) do
    finish(
      job_id,
      outcome,
      on_success,
      &Coordinator.commit_state_change/1,
      &Jobs.job_result/1
    )
  end

  @doc false
  @spec finish(
          String.t(),
          outcome(term()),
          (term() -> {Mutation.t(), term()}),
          (Mutation.t() -> commit_result()),
          (Jobs.Result.t() -> term())
        ) :: commit_result()
  def finish(job_id, {:ok, value}, on_success, commit, publish_result)
      when is_binary(job_id) and is_function(on_success, 1) and
             is_function(commit, 1) and is_function(publish_result, 1) do
    {change, result_data} = on_success.(value)
    publish(change, Jobs.Result.new(job_id, nil, result_data), commit, publish_result)
  end

  def finish(job_id, {:error, reason}, _on_success, _commit, publish_result)
      when is_binary(job_id) and is_function(publish_result, 1) do
    publish_result.(Jobs.Result.new(job_id, nil, :done, reason))
    {:error, reason}
  end

  @spec publish(Mutation.t(), Jobs.Result.t()) :: commit_result()
  def publish(%Mutation{} = change, %Jobs.Result{} = result) do
    publish(change, result, &Coordinator.commit_state_change/1, &Jobs.job_result/1)
  end

  @doc false
  @spec publish(
          Mutation.t(),
          Jobs.Result.t(),
          (Mutation.t() -> commit_result()),
          (Jobs.Result.t() -> term())
        ) :: commit_result()
  def publish(%Mutation{} = change, %Jobs.Result{} = result, commit, publish_result)
      when is_function(commit, 1) and is_function(publish_result, 1) do
    case commit.(change) do
      :ok ->
        publish_result.(result)
        :ok

      {:error, reason} ->
        publish_result.(%{result | error: {:state_change_failed, reason}})
        {:error, reason}
    end
  end
end
