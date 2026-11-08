defmodule ExdockClient.ApplicationTest do
  use ExUnit.Case, async: true

  test "test environment does not boot the standalone client supervision tree" do
    assert Application.spec(:exdock_client, :mod) == []
    refute Process.whereis(ExdockClient.Supervisor)
    refute Process.whereis(Exdock.Client.Connection.TCPClient)
  end
end
