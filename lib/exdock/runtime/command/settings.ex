defmodule Exdock.Runtime.Command.Settings do
  @moduledoc """
  Stable constructor facade for settings-related runtime commands.

  Validation and mutation mapping are owned by handlers aligned with each state
  domain.
  """

  alias Exdock.Configuration
  alias Exdock.Runtime.Command.Settings.{Container, Image, Node, User}

  @spec image_delete_lock(term(), String.t(), boolean()) :: Image.t()
  defdelegate image_delete_lock(node, image_id, locked), to: Image

  @spec image_repository_url(String.t(), String.t()) :: Image.t()
  defdelegate image_repository_url(image_name, repository_url), to: Image

  @spec image_repository_urls([{String.t(), String.t()}]) :: Image.t()
  defdelegate image_repository_urls(overrides), to: Image

  @spec container_priority(term(), String.t(), integer()) :: Container.t()
  defdelegate container_priority(node, name, priority), to: Container

  @spec container_priorities([{term(), String.t(), integer()}]) :: Container.t()
  defdelegate container_priorities(priorities), to: Container

  @spec container_auto_update(term(), String.t(), atom()) :: Container.t()
  defdelegate container_auto_update(node, name, policy), to: Container

  @spec user_setting(atom(), term()) :: User.t()
  defdelegate user_setting(key, value), to: User

  @spec node_setting(term(), atom(), term()) :: Node.t()
  defdelegate node_setting(node, key, value), to: Node

  @spec import(Configuration.t()) :: User.t()
  defdelegate import(configuration), to: User
end
