defmodule Exdock.ClientLib.Container.DockerOps do
  @moduledoc false

  alias Exdock.Docker

  def inspect(conn, id), do: Docker.Local.Container.inspect(conn, id)
  def inspect_image(conn, reference), do: Docker.Local.Image.inspect(conn, reference)
  def stop(conn, id), do: Docker.Local.Container.stop(conn, id)
  def rename(conn, id, name), do: Docker.Local.Container.rename(conn, id, name)
  def create(conn, name, request), do: Docker.Local.Container.create(conn, name, request)
  def start(conn, id), do: Docker.Local.Container.start(conn, id)
  def delete(conn, id), do: Docker.Local.Container.delete(conn, id)
  def disconnect(conn, network, request), do: Docker.Local.Network.disconnect(conn, network, request)
  def connect(conn, network, request), do: Docker.Local.Network.connect(conn, network, request)
end
