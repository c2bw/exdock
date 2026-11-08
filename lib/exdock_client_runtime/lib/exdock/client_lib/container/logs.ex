defmodule Exdock.ClientLib.Container.Logs do
  @moduledoc """
  Retrieves and decodes Docker container log streams.
  """

  alias Exdock.ClientLib.Container.LogDecoder
  alias Exdock.ClientLib.Utils
  alias Exdock.Docker
  alias Exdock.Docker.Error

  @spec get_log(Exdock.Docker.Engine.connection(), String.t(), keyword()) ::
          {:ok, [String.t()]} | {:error, Error.t()}
  def get_log(conn, container_id, opts \\ []) do
    case Docker.Local.Container.log(conn, container_id, opts) do
      {:ok, log} -> decode(log.body)
      {:error, error} -> {:error, Utils.docker_error(:container_logs, error)}
    end
  end

  defp decode(body) do
    case LogDecoder.decode(body) do
      {:ok, lines} ->
        {:ok, lines}

      {:error, :malformed_frame} ->
        {:error,
         Utils.docker_error(:container_logs, :malformed_frame, message: "Docker returned a malformed container log stream")}
    end
  end
end
