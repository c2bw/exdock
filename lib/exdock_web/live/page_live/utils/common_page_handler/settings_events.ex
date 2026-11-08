defmodule ExdockWeb.PageLive.Utils.CommonPageHandler.SettingsEvents do
  @moduledoc false

  alias Exdock.{Configuration, Operations}
  alias ExdockWeb.PageLive.Utils.{LiveOperation, SettingsTextParser}

  @spec handle(binary(), any(), Phoenix.LiveView.Socket.t()) ::
          {:handled, Phoenix.LiveView.Socket.t()} | :unhandled
  def handle(event, params, socket) do
    case {event, params} do
      {"import_repository_overrides", %{"repositories_input" => repositories}} ->
        handled(import_repository_overrides(socket, repositories))

      {"import_containers_priorities", %{"priorities_input" => priorities}} ->
        handled(import_containers_priorities(socket, priorities))

      {"import_server_configuration", %{"server_configuration" => settings}} ->
        handled(import_server_configuration(socket, settings))

      {"change_user_settings", %{"key" => key, "val" => value}} ->
        handled(change_user_setting(socket, key, value))

      {"change_node_settings", %{"node" => node, "key" => key, "val" => value}} ->
        handled(change_node_setting(socket, node, key, value))

      {"repository-url-update", %{"img_name" => image, "new_url" => new_url}} ->
        handled(command(socket, Operations.set_image_repository_url(image, new_url)))

      _ ->
        :unhandled
    end
  end

  defp import_repository_overrides(socket, repositories)
       when is_binary(repositories) or is_list(repositories) do
    case SettingsTextParser.repository_overrides(repositories) do
      {:ok, overrides} ->
        command(socket, Operations.set_image_repository_urls(overrides))

      {:error, :invalid_repository_overrides} ->
        LiveOperation.invalid(socket, "Invalid repository overrides")
    end
  end

  defp import_repository_overrides(socket, _repositories),
    do: LiveOperation.invalid(socket, "Invalid repository overrides")

  defp import_containers_priorities(socket, priorities)
       when is_binary(priorities) or is_list(priorities) do
    case SettingsTextParser.container_priorities(priorities) do
      {:ok, parsed_priorities} ->
        command(socket, Operations.set_container_priorities(parsed_priorities))

      {:error, :invalid_container_priorities} ->
        LiveOperation.invalid(socket, "Invalid container priorities")
    end
  end

  defp import_containers_priorities(socket, _priorities),
    do: LiveOperation.invalid(socket, "Invalid container priorities")

  defp import_server_configuration(socket, settings) when is_binary(settings) do
    case Configuration.from_json(settings) do
      {:ok, configuration} ->
        command(socket, Operations.import_server_configuration(configuration))

      {:error, error} ->
        Phoenix.LiveView.put_flash(
          socket,
          :error,
          "Configuration import: Jason Decode Error: #{error}"
        )
    end
  end

  defp import_server_configuration(socket, _settings),
    do: LiveOperation.invalid(socket, "Invalid server configuration")

  defp change_user_setting(socket, key, value) do
    case Operations.change_user_setting(key, value) do
      {:error, {:unknown_user_setting, _key}} ->
        Phoenix.LiveView.put_flash(socket, :error, "Unknown user setting")

      result ->
        command(socket, result)
    end
  end

  defp change_node_setting(socket, node, key, value) do
    case Operations.change_node_setting(node, key, value) do
      {:error, {:unknown_node_setting, _key}} ->
        Phoenix.LiveView.put_flash(socket, :error, "Unknown node setting")

      result ->
        command(socket, result)
    end
  end

  defp command(socket, result), do: LiveOperation.handle(socket, result)
  defp handled(socket), do: {:handled, socket}
end
