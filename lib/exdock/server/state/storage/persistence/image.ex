defmodule Exdock.Server.State.Storage.Persistence.Image do
  @moduledoc """
  Stable facade for runtime image persistence.

  Hydration and write orchestration live in dedicated modules so callers keep a
  compact persistence API without coupling to either implementation.
  """

  alias Exdock.Server.State.Storage.Persistence.Image.{Loader, Writer}

  defdelegate from_client(image, node, previous, in_use), to: Loader
  defdelegate load_metadata(image), to: Loader
  defdelegate reload_configuration(image), to: Loader
  defdelegate digest_in_db?(node, digest), to: Loader
  defdelegate load_node(node), to: Loader
  defdelegate load_id(node, id), to: Loader
  defdelegate load_digest(node, digest), to: Loader

  defdelegate same?(left, right), to: Writer
  defdelegate insert(image), to: Writer
  defdelegate insert_many(images), to: Writer
  defdelegate sync_node_set(node, image_ids), to: Writer
end
