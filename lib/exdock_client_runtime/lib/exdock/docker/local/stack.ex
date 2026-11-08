defmodule Exdock.Docker.Local.Stack do
  alias DockerEngineAPI.Model
  alias Exdock.Docker.Local.{Response, Types}

  @doc """
    Returns a list of all the containers which are part of a stack
  """
  @spec list(Types.connection()) :: Types.result(any())
  def list(conn) do
    DockerEngineAPI.Api.Container.container_list(conn,
      all: true,
      filter: %{label: ["com.docker.stack.namespace"]}
    )
    |> Response.reject_struct(Model.ErrorResponse)
  end
end
