defmodule Exdock.Server.State.Storage.Containers.Change do
  @moduledoc """
  Constructors for container storage change payloads.
  """

  alias Exdock.Runtime.Mutation
  alias Exdock.Domain.Container

  @doc """
  Add a new resources record for a container.
  """
  @spec resources(String.t(), String.t(), Container.Resources.Record.t()) :: Mutation.t()
  def resources(node, id, %Container.Resources.Record{} = resources)
      when is_binary(node) and is_binary(id) do
    Mutation.container_resources!(node, id, resources)
  end

  @doc """
  Add logs for a container.
  """
  @spec logs(String.t(), String.t(), [String.t()], DateTime.t()) :: Mutation.t()
  def logs(node, id, logs, %DateTime{} = occurred_at)
      when is_binary(node) and is_binary(id) and is_list(logs) do
    Mutation.container_logs!(node, id, logs, occurred_at)
  end
end
