defmodule Exdock.Server.State.Storage.Persistence.Container do
  @moduledoc """
  Stable facade for runtime container persistence.

  Hydration and write orchestration live in dedicated modules so callers keep a
  compact persistence API without coupling to either implementation.
  """

  alias Exdock.Server.State.Storage.Persistence.Container.{Loader, Writer}
  alias Exdock.Server.State.Storage.Persistence.LoadReport
  alias Exdock.Domain.Container, as: RuntimeContainer

  @type node_id :: Exdock.NodeId.t()

  defdelegate same?(left, right), to: Writer

  @spec load_node(node_id(), String.t(), boolean()) ::
          {:ok, [RuntimeContainer.t()]} | {:error, LoadReport.t(RuntimeContainer.t())}
  def load_node(node, platform, load_deleted \\ false) do
    Loader.load_node(node, platform, load_deleted)
  end

  @doc false
  defdelegate load_node(node, platform, load_deleted, opts), to: Loader

  @spec load(node_id(), String.t(), String.t(), boolean()) ::
          {:ok, RuntimeContainer.t() | :not_found} | {:error, term()}
  def load(node, container_name, platform, load_deleted \\ false) do
    Loader.load(node, container_name, platform, load_deleted)
  end

  defdelegate reload_settings(container), to: Loader
  defdelegate insert(container), to: Writer
  defdelegate insert_many(containers), to: Writer
  defdelegate sync_node_set(node, container_names), to: Writer
end
