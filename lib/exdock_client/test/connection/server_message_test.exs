defmodule Exdock.Client.Connection.ServerMessageTest do
  use ExUnit.Case, async: true

  alias Exdock.Client.Connection.ServerMessage
  alias Exdock.Protocol.{Contract, Message}

  test "normalizes terminal protocol errors" do
    frame = Contract.encode_term_frame(:error, :invalid_auth)

    assert {:server_error, {:authentication_error, :invalid_auth}} =
             ServerMessage.route(frame)
  end

  test "routes runtime bundles and commands as explicit actions" do
    bundle = %{"version" => "1", "digest" => "digest", "modules" => []}
    command = Message.command("job-id", "container_start", ["container"])

    assert {:runtime_bundle, ^bundle} =
             :runtime_bundle
             |> Contract.encode_term_frame(bundle)
             |> ServerMessage.route()

    assert {:execute, ^command} =
             :command
             |> Contract.encode_term_frame(command)
             |> ServerMessage.route()
  end

  test "classifies version, identity, and malformed protocol errors" do
    assert {:server_error, {:version_mismatch, :version_too_old}} =
             ServerMessage.route(<<3, 1>>)

    assert {:server_error, {:version_mismatch, :version_too_new}} =
             ServerMessage.route(<<5, 1>>)

    for reason <- [:duplicate_name, :invalid_name] do
      assert {:server_error, {:authentication_error, ^reason}} =
               :error
               |> Contract.encode_term_frame(reason)
               |> ServerMessage.route()
    end

    assert {:server_error, :malformed_message} = ServerMessage.route(<<4>>)
    assert {:unknown, {:heartbeat, ""}} = ServerMessage.route(<<4, 1>>)
  end
end
