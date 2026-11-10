defmodule Exdock.Client.Connection.ServerMessageTest do
  use ExUnit.Case, async: true

  alias Exdock.Client.Connection.ServerMessage
  alias Exdock.Protocol.{Contract, Message}

  test "normalizes terminal protocol errors" do
    frame = Contract.encode!(:error, :invalid_auth)

    assert {:server_error, {:authentication_error, :invalid_auth}} =
             ServerMessage.route(frame)
  end

  test "routes runtime bundles and commands as explicit actions" do
    modules =
      Enum.map(Exdock.Protocol.RuntimeBundle.required_modules(), fn module ->
        {module, <<0, 255>>, String.to_charlist(Atom.to_string(module) <> ".beam")}
      end)

    bundle = Exdock.Protocol.RuntimeBundle.build("1", modules)
    command = Message.command("job-id", "container_start", ["container"])

    assert {:runtime_bundle, ^bundle} =
             :runtime_bundle
             |> Contract.encode!(bundle)
             |> ServerMessage.route()

    assert {:execute, ^command} =
             :command
             |> Contract.encode!(command)
             |> ServerMessage.route()
  end

  test "classifies version, identity, and malformed protocol errors" do
    for reason <- [:duplicate_name, :invalid_name] do
      assert {:server_error, {:authentication_error, ^reason}} =
               :error
               |> Contract.encode!(reason)
               |> ServerMessage.route()
    end

    assert {:server_error, :malformed_message} = ServerMessage.route(<<4>>)
  end
end
