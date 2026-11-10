defmodule Exdock.Server.Connection.SessionTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Connection.{Session, WireMessage}

  test "moves through the handshake phases without contradictory flags" do
    session = Session.new()

    assert session.phase == :awaiting_hello
    assert Session.trust(session) == :untrusted
    refute Session.registered?(session)
    refute Session.ready?(session)

    session =
      session
      |> Session.identify("node-a")
      |> Session.authenticate()
      |> Session.offer_bundle("digest")

    assert session.phase == :awaiting_ready
    assert Session.trust(session) == :authenticated
    assert Session.registered?(session)
    refute Session.ready?(session)

    session = Session.initialize(session)

    assert session.phase == :ready
    assert Session.ready?(session)
  end

  test "routes only messages valid for the current phase" do
    awaiting_hello = Session.new()

    assert {:authenticate, "1.2.0", "token", "node-a"} =
             Session.route(awaiting_hello, {:hello, "1.2.0", "token", "node-a"})

    assert {:stop, :unauthorized} =
             Session.route(awaiting_hello, {:client_message, :too_early})

    awaiting_ready =
      awaiting_hello
      |> Session.identify("node-a")
      |> Session.authenticate()

    assert {:initialize, "1", "digest", %{}} =
             Session.route(awaiting_ready, {:ready, "1", "digest", %{}})

    assert {:stop, :unexpected_message} =
             Session.route(awaiting_ready, {:client_message, :too_early})

    ready =
      awaiting_ready
      |> Session.offer_bundle("digest")
      |> Session.initialize()

    result = WireMessage.result("job-id", "container_start", "node-a", "container-id", nil)
    assert {:job_result, ^result} = Session.route(ready, {:client_message, result})
    assert {:client_message, :payload} = Session.route(ready, {:client_message, :payload})
  end
end
