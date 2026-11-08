defmodule Exdock.Server.Connection.Handler.LifecycleTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Connection.Handler.Lifecycle
  alias Exdock.Server.Connection.Session

  test "initialization timeout only keeps ready sessions" do
    awaiting_hello = Session.new()
    assert Lifecycle.decide(:initialization_timeout, awaiting_hello) == {:stop, :client_init_timeout}

    ready =
      awaiting_hello
      |> Session.identify("node")
      |> Session.authenticate()
      |> Session.offer_bundle("digest")
      |> Session.initialize()

    assert Lifecycle.decide(:initialization_timeout, ready) == :continue
  end

  test "transport failures map to explicit stop decisions" do
    session = Session.new()

    assert Lifecycle.decide(:socket_closed, session) == {:stop, :normal}
    assert Lifecycle.decide({:socket_error, :closed}, session) == {:stop, :closed}
    assert Lifecycle.decide(:heartbeat_timeout, session) == {:stop, :heartbeat_timeout}
  end
end
