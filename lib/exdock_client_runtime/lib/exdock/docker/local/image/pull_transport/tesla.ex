defmodule Exdock.Docker.Local.Image.PullTransport.Tesla do
  @moduledoc """
  Tesla/Hackney adapter required by the generated Docker Engine client.
  """

  @behaviour Exdock.Docker.Local.Image.PullTransport

  @impl true
  def stream(conn, image_tag, consumer_pid) do
    query = URI.encode_query(fromImage: image_tag)

    Tesla.post(conn, "/images/create?#{query}", "", opts: [adapter: [async: true, stream_to: consumer_pid]])
  rescue
    exception -> {:error, exception}
  catch
    kind, reason -> {:error, {kind, reason}}
  end
end
