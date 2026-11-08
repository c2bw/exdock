defmodule Exdock.ClientLib.Container do
  @moduledoc """
  Public facade for client-side Docker container operations.

  Focused modules own lifecycle actions, inventory collection, logs, and
  resource sampling while this module preserves the runtime API.
  """

  alias Exdock.ClientLib.Container.{Actions, Inventory, Logs, Resources}
  alias Exdock.Docker.Error
  alias Exdock.Protocol.Snapshot.Container, as: ContainerSnapshot

  @type t :: ContainerSnapshot.t()

  @spec recreate(Exdock.Docker.Engine.connection(), String.t(), atom(), String.t() | nil) ::
          {:ok, Exdock.ClientLib.Container.Recreator.success()} | {:error, Error.t()}
  defdelegate recreate(conn, container_identifier, job_name, job_id \\ nil), to: Actions

  @spec start(Exdock.Docker.Engine.connection(), String.t()) :: {:ok, term()} | {:error, Error.t()}
  defdelegate start(conn, id), to: Actions

  @spec stop(Exdock.Docker.Engine.connection(), String.t()) :: {:ok, term()} | {:error, Error.t()}
  defdelegate stop(conn, id), to: Actions

  @spec restart(Exdock.Docker.Engine.connection(), String.t()) :: {:ok, term()} | {:error, Error.t()}
  defdelegate restart(conn, id), to: Actions

  @spec image_info(Exdock.Docker.Engine.connection(), String.t()) ::
          {:ok, %{image_tag: String.t(), image_id: String.t()}} | {:error, Error.t()}
  defdelegate image_info(conn, id), to: Inventory

  @spec get_all(Exdock.Docker.Engine.connection(), boolean(), keyword()) ::
          {:ok, %{ok: [t()], errored: [{Error.t(), t()}]}} | {:error, Error.t()}
  defdelegate get_all(conn, retrieve_resources, opts \\ [status: :all]), to: Inventory

  @spec get_log(Exdock.Docker.Engine.connection(), String.t(), keyword()) :: {:ok, [String.t()]} | {:error, Error.t()}
  defdelegate get_log(conn, container_id, opts \\ []), to: Logs

  @spec get_resources(Exdock.Docker.Engine.connection(), String.t()) ::
          {:ok, DockerEngineAPI.Model.ContainerStatsResponse.t()} | {:error, Error.t()}
  defdelegate get_resources(conn, container_id), to: Resources
end
