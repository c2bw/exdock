defmodule Exdock.Server.State.Storage.Cluster.Persistence do
  @moduledoc """
  Executes a cluster reconciliation persistence plan.

  Database synchronization and inserts live here so reconciliation remains an
  in-memory operation and persistence ordering stays explicit.
  """

  alias Exdock.Server.State.Storage
  alias Exdock.Server.State.Storage.Cluster.Persistence.Plan
  alias Exdock.Server.State.Storage.Persistence.Container, as: ContainerPersistence
  alias Exdock.Server.State.Storage.Persistence.Image, as: ImagePersistence
  alias Exdock.Server.State.Storage.Persistence.Node, as: NodePersistence
  alias Exdock.Server.State.Storage.Persistence.{Result, Transaction}

  @spec persist(Plan.t()) :: {:ok, Plan.t()} | {:error, term()}
  def persist(%Plan{} = plan) do
    Transaction.run(fn ->
      with :ok <- sync_image_set(plan),
           :ok <- sync_container_set(plan),
           :ok <- persist_record(plan.node_record, Storage.Nodes, &NodePersistence.insert/1),
           :ok <- ImagePersistence.insert_many(plan.images),
           :ok <- ContainerPersistence.insert_many(plan.containers) do
        {:ok, plan}
      end
    end)
  end

  defp sync_image_set(%Plan{image_ids: nil}), do: :ok

  defp sync_image_set(%Plan{node: node, image_ids: image_ids}) do
    ImagePersistence.sync_node_set(node, image_ids)
  end

  defp sync_container_set(%Plan{container_names: nil}), do: :ok

  defp sync_container_set(%Plan{node: node, container_names: container_names}) do
    ContainerPersistence.sync_node_set(node, container_names)
  end

  defp persist_record(nil, _storage_module, _insert), do: :ok

  defp persist_record(record, storage_module, insert) do
    insert.(record)
    |> Result.normalize_write_result(storage_module)
  end
end
