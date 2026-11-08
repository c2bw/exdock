defmodule ExdockWeb.PageLive.Utils.CommonPageHandler.CommandEvents do
  @moduledoc false

  alias Exdock.Operations
  alias ExdockWeb.PageLive.Utils.{EventParams, LiveOperation}

  @spec handle(binary(), any(), Phoenix.LiveView.Socket.t()) ::
          {:handled, Phoenix.LiveView.Socket.t()} | :unhandled
  def handle(event, params, socket) do
    case {event, params} do
      {"node_refresh_cluster", _} ->
        handled(command(socket, Operations.refresh_cluster()))

      {"node_refresh", %{"nodename" => node}} ->
        handled(command(socket, Operations.refresh_node(node)))

      {"registry_fetch", _} ->
        handled(command(socket, Operations.fetch_registry_cluster()))

      {"registry_fetch_node", %{"nodename" => node}} ->
        handled(command(socket, Operations.fetch_registry_node(node)))

      {"image-pull", params} ->
        handled(image_pull(socket, params))

      {"image_delete", params} ->
        handled(image_delete(socket, params))

      {"image_delete_unused", params} ->
        handled(image_cleanup(socket, params))

      {"image_delete_lock", params} ->
        handled(image_lock(socket, params))

      {"container-start", %{"node" => node, "container_name" => name}} ->
        handled(command(socket, Operations.start_container(node, name)))

      {"container-stop", %{"node" => node, "container_name" => name}} ->
        handled(command(socket, Operations.stop_container(node, name)))

      {"container-restart", %{"node" => node, "container_name" => name}} ->
        handled(command(socket, Operations.restart_container(node, name)))

      {"container-logs", %{"node" => node, "container_name" => name}} ->
        handled(command(socket, Operations.fetch_container_logs(node, name)))

      {"container-recreate", params} ->
        handled(container_recreate(socket, params))

      {"clear_errors", _} ->
        handled(command(socket, Operations.clear_errors()))

      _ ->
        :unhandled
    end
  end

  defp image_pull(socket, params) do
    case EventParams.image_jobs(params) do
      {:ok, jobs} ->
        command(socket, Operations.pull_images(jobs))

      {:error, :invalid_image_jobs} ->
        LiveOperation.invalid(socket, "Invalid image pull request")
    end
  end

  defp image_delete(socket, params) do
    case EventParams.image_delete(params) do
      {:ok, {node, image_id}} -> command(socket, Operations.delete_image(node, image_id))
      {:error, :invalid_image_delete} -> LiveOperation.invalid(socket, "Invalid image delete request")
    end
  end

  defp image_cleanup(socket, params) do
    case EventParams.image_cleanup(params) do
      {:ok, node} -> command(socket, Operations.delete_unused_images(node))
      {:error, :invalid_image_cleanup} -> LiveOperation.invalid(socket, "Invalid image cleanup request")
    end
  end

  defp image_lock(socket, params) do
    case EventParams.image_lock(params) do
      {:ok, {node, image_id, lock?}} ->
        command(socket, Operations.set_image_delete_lock(node, image_id, lock?))

      {:error, :invalid_image_lock} ->
        LiveOperation.invalid(socket, "Invalid image lock request")
    end
  end

  defp container_recreate(socket, %{"image_pull" => pull_image} = params) do
    with {:ok, containers} <- EventParams.container_jobs(params),
         {:ok, pull_image?} <- EventParams.boolean(pull_image) do
      command(socket, Operations.recreate_containers(containers, pull_image?))
    else
      {:error, _reason} -> LiveOperation.invalid(socket, "Invalid container recreate request")
    end
  end

  defp container_recreate(socket, _params),
    do: LiveOperation.invalid(socket, "Invalid container recreate request")

  defp command(socket, result), do: LiveOperation.handle(socket, result)
  defp handled(socket), do: {:handled, socket}
end
