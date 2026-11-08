defmodule Exdock.Operations do
  @moduledoc """
  Stable command boundary for operator-initiated Exdock work.

  Commands accept external domain values (notably string node identifiers) and
  return an opaque operation id as soon as the runtime accepts them. Progress
  and completion are delivered through `Exdock.Events`.
  """

  alias Exdock.Runtime
  alias Exdock.Runtime.Command

  @type operation_id :: Ecto.UUID.t()
  @type result :: {:ok, operation_id()} | {:error, term()}
  @type node_id :: Exdock.NodeId.t()
  @type log_condition :: :normal | :hidden | :no
  @type auto_update_policy :: :enabled | :disabled | :passthrough
  @type user_setting_key :: Exdock.Settings.UserFieldCatalog.key()
  @type user_setting_value :: Exdock.Settings.UserFieldCatalog.value()

  @spec refresh_cluster(log_condition()) :: result()
  def refresh_cluster(log_condition \\ :normal),
    do: submit(Command.Cluster.refresh_cluster(log_condition))

  @spec refresh_node(node_id(), log_condition()) :: result()
  def refresh_node(node, log_condition \\ :normal),
    do: submit(Command.Cluster.refresh_node(node, log_condition))

  @spec fetch_registry_cluster() :: result()
  def fetch_registry_cluster,
    do: submit(Command.Cluster.fetch_registry_cluster())

  @spec fetch_registry_node(node_id()) :: result()
  def fetch_registry_node(node),
    do: submit(Command.Cluster.fetch_registry_node(node))

  @spec pull_images([%{required(:node) => node_id(), required(:image_tag) => String.t()}]) :: result()
  def pull_images(images), do: submit(Command.Image.pull(images))

  @spec delete_image(node_id(), String.t()) :: result()
  def delete_image(node, image_id),
    do: submit(Command.Image.delete(node, image_id))

  @spec delete_unused_images(node_id()) :: result()
  def delete_unused_images(node),
    do: submit(Command.Image.delete_unused(node))

  @spec recreate_containers([{node_id(), String.t()}], boolean()) :: result()
  def recreate_containers(containers, pull_image),
    do: submit(Command.Container.recreate(containers, pull_image))

  @spec start_container(node_id(), String.t()) :: result()
  def start_container(node, name),
    do: submit(Command.Container.start(node, name))

  @spec stop_container(node_id(), String.t()) :: result()
  def stop_container(node, name),
    do: submit(Command.Container.stop(node, name))

  @spec restart_container(node_id(), String.t()) :: result()
  def restart_container(node, name),
    do: submit(Command.Container.restart(node, name))

  @spec fetch_container_logs(node_id(), String.t()) :: result()
  def fetch_container_logs(node, name),
    do: submit(Command.Container.logs(node, name))

  @spec fetch_repositories([String.t()]) :: result()
  def fetch_repositories(repositories),
    do: submit(Command.Repository.fetch(repositories))

  @spec fetch_releases([atom()]) :: result()
  def fetch_releases(filter \\ [:ok, :rate_limit]),
    do: submit(Command.Repository.fetch_releases(filter))

  @spec set_image_delete_lock(node_id(), String.t(), boolean()) :: result()
  def set_image_delete_lock(node, image_id, locked),
    do: submit(Command.Settings.image_delete_lock(node, image_id, locked))

  @spec set_image_repository_url(String.t(), String.t()) :: result()
  def set_image_repository_url(image_name, repository_url),
    do: submit(Command.Settings.image_repository_url(image_name, repository_url))

  @spec set_image_repository_urls([{String.t(), String.t()}]) :: result()
  def set_image_repository_urls(overrides),
    do: submit(Command.Settings.image_repository_urls(overrides))

  @spec set_container_priority(node_id(), String.t(), integer()) :: result()
  def set_container_priority(node, name, priority),
    do: submit(Command.Settings.container_priority(node, name, priority))

  @spec set_container_priorities([{node_id(), String.t(), integer()}]) :: result()
  def set_container_priorities(priorities),
    do: submit(Command.Settings.container_priorities(priorities))

  @spec set_container_auto_update(node_id(), String.t(), auto_update_policy()) :: result()
  def set_container_auto_update(node, name, policy),
    do: submit(Command.Settings.container_auto_update(node, name, policy))

  @spec change_user_setting(user_setting_key(), user_setting_value()) :: result()
  def change_user_setting(key, value),
    do: submit(Command.Settings.user_setting(key, value))

  @spec change_node_setting(node_id(), :web_ui, String.t()) :: result()
  def change_node_setting(node, key, value),
    do: submit(Command.Settings.node_setting(node, key, value))

  @spec set_cron_string(String.t()) :: result()
  def set_cron_string(cron),
    do: submit(Command.Settings.user_setting(:cron_string, cron))

  @spec import_server_configuration(Exdock.Configuration.t()) :: result()
  def import_server_configuration(configuration),
    do: submit(Command.Settings.import(configuration))

  @spec run_automation() :: result()
  def run_automation, do: submit(:run_automation)

  @spec clear_errors() :: result()
  def clear_errors, do: submit(:clear_errors)

  defp submit(command) do
    operation_id = Ecto.UUID.generate()

    case Runtime.dispatch(operation_id, command) do
      :ok -> {:ok, operation_id}
      {:error, _reason} = error -> error
    end
  end
end
