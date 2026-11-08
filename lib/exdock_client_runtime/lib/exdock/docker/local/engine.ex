defmodule Exdock.Docker.Engine.Local do
  @moduledoc """
  Default Docker Engine adapter backed by the generated local API client.
  """

  @behaviour Exdock.Docker.Engine

  alias Exdock.ClientLib.{Container, Image}

  @impl true
  def connect, do: DockerEngineAPI.Connection.new()

  @impl true
  def list_containers(conn, retrieve_resources, opts),
    do: Container.get_all(conn, retrieve_resources, opts)

  @impl true
  def container_image_info(conn, id), do: Container.image_info(conn, id)

  @impl true
  def recreate_container(conn, id, job_name, job_id),
    do: Container.recreate(conn, id, job_name, job_id)

  @impl true
  def start_container(conn, id), do: Container.start(conn, id)

  @impl true
  def stop_container(conn, id), do: Container.stop(conn, id)

  @impl true
  def restart_container(conn, id), do: Container.restart(conn, id)

  @impl true
  def container_logs(conn, id, opts), do: Container.get_log(conn, id, opts)

  @impl true
  def container_resources(conn, id), do: Container.get_resources(conn, id)

  @impl true
  def list_images(conn), do: Image.get_all(conn)

  @impl true
  def pull_image(conn, tag, stream_response, job_name, job_id),
    do: Image.pull(conn, tag, stream_response, job_name, job_id)

  @impl true
  def delete_image(conn, id), do: Image.delete(conn, id)
end
