defmodule Exdock.ClientLib.Container.RecreatorTest.RollbackFailOps do
  @moduledoc false

  defdelegate inspect(agent, id), to: Exdock.ContainerRecreatorFakeOps
  defdelegate inspect_image(agent, reference), to: Exdock.ContainerRecreatorFakeOps
  defdelegate stop(agent, id), to: Exdock.ContainerRecreatorFakeOps
  defdelegate rename(agent, id, name), to: Exdock.ContainerRecreatorFakeOps
  defdelegate create(agent, name, request), to: Exdock.ContainerRecreatorFakeOps
  defdelegate delete(agent, id), to: Exdock.ContainerRecreatorFakeOps
  defdelegate disconnect(agent, network, request), to: Exdock.ContainerRecreatorFakeOps
  defdelegate connect(agent, network, request), to: Exdock.ContainerRecreatorFakeOps

  def start(agent, "original-id") do
    state = Agent.get(agent, & &1)

    if state.secondary_failure == {:start, "original-id"} do
      {:error, :rollback_failure}
    else
      Exdock.ContainerRecreatorFakeOps.start(agent, "original-id")
    end
  end

  def start(agent, id), do: Exdock.ContainerRecreatorFakeOps.start(agent, id)
end
