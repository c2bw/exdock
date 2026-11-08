defmodule Exdock.Server.Connection.DispatchedJobs do
  @moduledoc """
  Pure correlation state for commands dispatched through one agent connection.

  Timer creation and cancellation are effects owned by the connection handler.
  This module records timer references and returns them to the handler when they
  need to be cancelled.
  """

  alias Exdock.Protocol.Messages.JobResult
  alias Exdock.Protocol.Command
  alias Exdock.Server.Connection.WireMessage
  alias Exdock.Server.Jobs.{Job, Result}

  @type entry :: %{job: Job.t(), timer: reference(), token: reference()}
  @type t :: %{optional(String.t()) => entry()}
  @type correlation_error :: :unknown_job | :job_mismatch | :node_mismatch

  @spec new() :: t()
  def new, do: %{}

  @spec track(t(), Job.t(), reference(), reference()) :: {t(), reference() | nil}
  def track(entries, %Job{id: id, name: name} = job, timer, token)
      when is_map(entries) and is_binary(id) and is_atom(name) and
             is_reference(timer) and is_reference(token) do
    previous_timer =
      case Map.get(entries, id) do
        %{timer: previous_timer} -> previous_timer
        nil -> nil
      end

    {Map.put(entries, id, %{job: job, timer: timer, token: token}), previous_timer}
  end

  @spec correlate(t(), String.t(), WireMessage.t()) ::
          {:ok, t(), reference(), Job.t()} | {:error, correlation_error()}
  def correlate(
        entries,
        client_name,
        %WireMessage{type: :result, id: job_id, kind: kind, node: node}
      )
      when is_map(entries) and is_binary(client_name) and is_binary(job_id) and is_binary(kind) do
    with true <- result_node_matches?(node, client_name),
         {:ok, %{job: %Job{} = job, timer: timer}} <- Map.fetch(entries, job_id),
         {:ok, ^kind} <- Command.external(job.name) do
      {:ok, Map.delete(entries, job_id), timer, job}
    else
      false -> {:error, :node_mismatch}
      :error -> {:error, :unknown_job}
      {:ok, _other_kind} -> {:error, :job_mismatch}
    end
  end

  def correlate(entries, client_name, %WireMessage{})
      when is_map(entries) and is_binary(client_name),
      do: {:error, :job_mismatch}

  @spec expire(t(), String.t(), String.t(), reference()) ::
          {:ok, t(), reference(), JobResult.t()} | {:error, :unknown_job}
  def expire(entries, client_name, job_id, token)
      when is_map(entries) and is_binary(client_name) and is_binary(job_id) and
             is_reference(token) do
    case Map.fetch(entries, job_id) do
      {:ok, %{job: %Job{} = job, timer: timer, token: ^token}} ->
        result = Result.new(job_id, client_name, nil, :client_job_timeout)
        message = JobResult.new(job, result)
        {:ok, Map.delete(entries, job_id), timer, message}

      _unknown_job ->
        {:error, :unknown_job}
    end
  end

  defp result_node_matches?(node, client_name) when is_binary(node),
    do: node == client_name

  defp result_node_matches?(_node, _client_name), do: false
end
