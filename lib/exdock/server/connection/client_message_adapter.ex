defmodule Exdock.Server.Connection.ClientMessageAdapter do
  @moduledoc """
  Converts authenticated wire DTOs to internal job and state messages.
  """

  alias Exdock.Protocol.Command
  alias Exdock.Protocol.Messages.{AsyncResult, JobResult, Update}
  alias Exdock.Server.Connection.WireMessage
  alias Exdock.Server.Jobs.{Job, Result}

  @type error :: :invalid_wire_message | {:unknown_command, String.t()}

  @spec to_internal(WireMessage.t()) ::
          {:ok, AsyncResult.t() | Update.t()} | {:error, error()}

  def to_internal(%WireMessage{type: :progress, id: id, kind: kind, node: node, data: data}) do
    with {:ok, name} <- internal_command(kind) do
      {:ok, Update.new(id, name, data) |> Update.set_node(node)}
    end
  end

  def to_internal(%WireMessage{type: :resource_sample, id: id, node: node, data: sample}) do
    {:ok, AsyncResult.new(node, :container_resources, id, sample)}
  end

  def to_internal(%WireMessage{}), do: {:error, :invalid_wire_message}

  @spec to_job_result(WireMessage.t(), Job.t()) :: {:ok, JobResult.t()} | {:error, :invalid_wire_message}
  def to_job_result(
        %WireMessage{type: :result, id: id, node: node, data: data, error: error},
        %Job{id: id} = job
      ) do
    {:ok, JobResult.new(job, Result.new(id, node, data, error))}
  end

  def to_job_result(%WireMessage{}, %Job{}), do: {:error, :invalid_wire_message}

  defp internal_command(kind) when is_binary(kind) do
    case Command.internal(kind) do
      {:ok, name} -> {:ok, name}
      :error -> {:error, {:unknown_command, kind}}
    end
  end

  defp internal_command(_kind), do: {:error, :invalid_wire_message}
end
