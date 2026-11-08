defmodule Exdock.ClientLib.Container.Actions do
  @moduledoc """
  Executes lifecycle-changing Docker container commands.
  """

  alias Exdock.ClientLib.Container.Recreator
  alias Exdock.ClientLib.Utils
  alias Exdock.Docker
  alias Exdock.Docker.Error

  @spec recreate(Exdock.Docker.Engine.connection(), String.t(), atom(), String.t() | nil) ::
          {:ok, Exdock.ClientLib.Container.Recreator.success()} | {:error, Error.t()}
  def recreate(conn, container_identifier, job_name, job_id \\ nil)
      when is_binary(container_identifier) do
    Recreator.recreate(conn, container_identifier, job_name, job_id)
  end

  @spec start(Exdock.Docker.Engine.connection(), String.t()) :: {:ok, term()} | {:error, Error.t()}
  def start(conn, id) when is_binary(id) do
    conn
    |> Docker.Local.Container.start(id)
    |> normalize(:container_start)
  end

  @spec stop(Exdock.Docker.Engine.connection(), String.t()) :: {:ok, term()} | {:error, Error.t()}
  def stop(conn, id) when is_binary(id) do
    conn
    |> Docker.Local.Container.stop(id)
    |> normalize(:container_stop)
  end

  @spec restart(Exdock.Docker.Engine.connection(), String.t()) :: {:ok, term()} | {:error, Error.t()}
  def restart(conn, id) when is_binary(id) do
    conn
    |> Docker.Local.Container.restart(id)
    |> normalize(:container_restart)
  end

  defp normalize({:ok, response}, _operation), do: {:ok, response}
  defp normalize({:error, error}, operation), do: {:error, Utils.docker_error(operation, error)}
end
