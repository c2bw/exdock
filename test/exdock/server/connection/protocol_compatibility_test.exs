Code.require_file(Path.expand("../../../../lib/exdock_client/lib/connection/protocol.ex", __DIR__))

defmodule Exdock.Server.Connection.ProtocolCompatibilityTest do
  use ExUnit.Case, async: true

  alias Exdock.Client.Connection.Protocol, as: ClientProtocol
  alias Exdock.Protocol.Message
  alias Exdock.Server.Connection.Protocol, as: ServerProtocol
  alias Exdock.Server.Connection.WireMessage

  test "client decodes every server-originated frame" do
    modules =
      Enum.map(Exdock.Protocol.RuntimeBundle.required_modules(), fn module ->
        {module, <<0, 255>>, String.to_charlist(Atom.to_string(module) <> ".beam")}
      end)

    bundle = Exdock.Protocol.RuntimeBundle.build("1", modules)
    command = Message.command("job-1", :container_start, ["container"])
    refresh_command = Message.command("refresh-1", :node_refresh, [%{"retrieve_resources" => true}])

    assert {:error, :shutdown} = ClientProtocol.decode_message(ServerProtocol.encode_message({:error, :shutdown}))

    assert {:runtime_bundle, ^bundle} =
             ClientProtocol.decode_message(ServerProtocol.encode_message({:runtime_bundle, bundle}))

    assert {:command, %{"id" => "job-1", "kind" => "container_start"}} =
             ClientProtocol.decode_message(ServerProtocol.encode_message({:command, command}))

    assert {:command,
            %{
              "id" => "refresh-1",
              "kind" => "node_refresh",
              "args" => [%{"retrieve_resources" => true}]
            }} =
             ClientProtocol.decode_message(ServerProtocol.encode_message({:command, refresh_command}))
  end

  test "server decodes every client-originated frame" do
    hello = %{"agent_version" => "1.2.0", "auth_token" => "token", "node" => "node"}

    metadata = %{
      "platform" => "linux/amd64",
      "agent_version" => "1.2.0",
      "elixir_version" => "1.18.4",
      "otp_release" => "27"
    }

    ready = %{"bundle_version" => "1", "digest" => "digest", "metadata" => metadata}
    progress = Message.progress("job-1", "container_start", "node", "starting")
    result = Message.result("job-1", "container_start", "node", "container", nil)
    sample = Message.resource_sample("node", "container", %{read: 1})

    assert {:hello, "1.2.0", "token", "node"} =
             ServerProtocol.decode_message(ClientProtocol.encode_message({:hello, hello}))

    assert {:ready, "1", "digest", ^metadata} =
             ServerProtocol.decode_message(ClientProtocol.encode_message({:ready, ready}), :authenticated)

    assert {:client_message, %WireMessage{type: :progress}} =
             ServerProtocol.decode_message(ClientProtocol.encode_message({:progress, progress}), :authenticated)

    assert {:client_message, %WireMessage{type: :result}} =
             ServerProtocol.decode_message(ClientProtocol.encode_message({:result, result}), :authenticated)

    assert {:client_message, %WireMessage{type: :resource_sample}} =
             ServerProtocol.decode_message(ClientProtocol.encode_message({:resource_sample, sample}), :authenticated)
  end

  test "preserves the log container identity and arbitrary output bytes" do
    logs = [<<0, 255>>, :binary.copy(<<255>>, 530_000), <<>>]
    result = Message.result("job-logs", "container_logs", "node", {"container", logs}, nil)
    frame = ClientProtocol.encode_message({:result, result})

    assert {:client_message, %WireMessage{type: :result, data: {"container", ^logs}}} =
             ServerProtocol.decode_message(frame, :authenticated)
  end
end
