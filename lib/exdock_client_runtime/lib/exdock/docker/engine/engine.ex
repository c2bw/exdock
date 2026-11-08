defmodule Exdock.Docker.Engine do
  @moduledoc """
  Agent-side boundary for local Docker Engine operations.

  The generated OpenAPI client is an implementation detail of the default
  adapter. Agent jobs depend on this behavior so connection and transport types
  do not spread through command orchestration.
  """

  alias Exdock.Docker.Error

  @type connection :: term()
  @type result(value) :: {:ok, value} | {:error, Error.t()}

  @callback connect() :: connection()
  @callback list_containers(connection(), boolean(), keyword()) :: result(map())
  @callback container_image_info(connection(), String.t()) :: result(map())
  @callback recreate_container(connection(), String.t(), atom(), String.t() | nil) ::
              result(String.t() | %{id: String.t(), warning: String.t()})
  @callback start_container(connection(), String.t()) :: result(term())
  @callback stop_container(connection(), String.t()) :: result(term())
  @callback restart_container(connection(), String.t()) :: result(term())
  @callback container_logs(connection(), String.t(), keyword()) :: result([String.t()])
  @callback container_resources(connection(), String.t()) :: result(term())
  @callback list_images(connection()) :: result(map())
  @callback pull_image(connection(), String.t(), boolean(), atom() | nil, String.t() | nil) :: result(term())
  @callback delete_image(connection(), String.t()) :: result(term())

  @spec adapter() :: module()
  def adapter do
    case Application.fetch_env(:exdock, :docker_engine_adapter) do
      {:ok, adapter} -> adapter
      :error -> Application.fetch_env!(:exdock_client, :docker_engine_adapter)
    end
  end
end
