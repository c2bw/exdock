defmodule Exdock.Docker.Remote.RegistryClientTest do
  use ExUnit.Case, async: true

  alias Exdock.Docker.Remote.RegistryClient
  alias Regc.Client

  test "returns one reusable client and closes its state on shutdown" do
    owner = start_supervised!({RegistryClient, name: nil})

    assert %Client{} = client = RegistryClient.get(owner)
    assert RegistryClient.get(owner) == client
    assert is_pid(client.state)

    state_monitor = Process.monitor(client.state)
    assert :ok = stop_supervised(RegistryClient)
    assert_receive {:DOWN, ^state_monitor, :process, _pid, :shutdown}
  end
end
