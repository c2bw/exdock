defmodule Exdock.Server.State.EffectRunner.Broadcast do
  @moduledoc false

  alias Exdock.Server.Broadcast
  alias Exdock.Server.State
  alias Exdock.Server.State.ConfigurationProjection
  alias Exdock.Server.State.Domain
  alias Exdock.Server.State.Storage

  def run(%State{} = state, {:broadcast, domain, requested_opts}) do
    {data, default_opts} = Domain.broadcast_payload(domain, state)

    opts =
      requested_opts
      |> Kernel.||(default_opts)
      |> Keyword.put(:revision, state.revision)

    State.broadcast_helper(domain, data, opts)
  end

  def run(%State{} = state, {:broadcast_projection, :cluster_info}) do
    Broadcast.broadcast(:cluster_info, Storage.Cluster.info(state), revision: state.revision)
  end

  def run(
        %State{settings: %Storage.Settings{}} = state,
        {:broadcast_projection, :server_configuration}
      ) do
    Broadcast.broadcast(
      :server_configuration,
      ConfigurationProjection.from_state(state),
      revision: state.revision
    )
  end

  def run(%State{}, {:broadcast_projection, :server_configuration}), do: :ok
end
