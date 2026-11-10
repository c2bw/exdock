defmodule Exdock.Client.Connection.ProtocolTest do
  use ExUnit.Case, async: true

  alias Exdock.Client.Connection.Protocol
  alias Exdock.Protocol.{Contract, Message}

  @version 4

  test "round trips client lifecycle messages" do
    hello = %{"agent_version" => "1.2.0", "auth_token" => "token", "node" => "node-a"}

    ready = %{
      "bundle_version" => "1",
      "digest" => "digest",
      "metadata" => %{
        "platform" => "linux/amd64",
        "agent_version" => "1.2.0",
        "elixir_version" => "1.18.4",
        "otp_release" => "27"
      }
    }

    assert {:ok, {:hello, _payload}} = Protocol.encode_message({:hello, hello}) |> Contract.decode()
    assert {:ok, {:ready, _payload}} = Protocol.encode_message({:ready, ready}) |> Contract.decode()
  end

  test "decodes runtime bundles and allowlisted commands" do
    modules =
      Enum.map(Exdock.Protocol.RuntimeBundle.required_modules(), fn module ->
        {module, <<0, 255>>, String.to_charlist(Atom.to_string(module) <> ".beam")}
      end)

    bundle = Exdock.Protocol.RuntimeBundle.build("1", modules)
    command = Message.command("job-id", "container_start", ["container"])

    refresh_command =
      Message.command("refresh-id", "node_refresh", [%{"retrieve_resources" => true}])

    assert {:runtime_bundle, ^bundle} =
             Contract.encode!(:runtime_bundle, bundle) |> Protocol.decode_message()

    assert {:command, ^command} = Contract.encode!(:command, command) |> Protocol.decode_message()

    assert {:command, ^refresh_command} =
             Contract.encode!(:command, refresh_command) |> Protocol.decode_message()
  end

  test "encodes result, progress, and resource payloads" do
    result = Message.result("job-id", "container_start", "node-a", "container", nil)
    progress = Message.progress("job-id", "container_start", "node-a", "starting")
    sample = Message.resource_sample("node-a", "container", %{read: 1})

    assert {:ok, {:result, _payload}} = Protocol.encode_message({:result, result}) |> Contract.decode()
    assert {:ok, {:progress, _payload}} = Protocol.encode_message({:progress, progress}) |> Contract.decode()

    assert {:ok, {:resource_sample, _payload}} =
             Protocol.encode_message({:resource_sample, sample}) |> Contract.decode()
  end

  test "rejects arbitrary commands and malformed bundles" do
    arbitrary = %{"id" => "job-id", "kind" => "arbitrary_rpc", "args" => [Kernel, :to_string]}

    assert {:error, :malformed_message} =
             Contract.encode!(:command, arbitrary) |> Protocol.decode_message()

    {:ok, invalid_bundle} =
      Exdock.Protocol.NodeWire.encode(:runtime_bundle, %{"version" => "1", "digest" => "digest", "modules" => %{}})

    assert {:error, :malformed_message} = Protocol.decode_message(invalid_bundle)
  end

  test "rejects malformed and incompatible frames" do
    assert {:error, :malformed_message} = Protocol.decode_message(<<@version>>)
    assert {:error, :malformed_message} = Protocol.decode_message(<<3, 1>>)
    assert {:error, :malformed_message} = Protocol.decode_message(<<5, 1>>)
    assert {:error, :malformed_message} = Protocol.decode_message(<<@version, 255>>)
    assert {:error, :malformed_message} = Protocol.decode_message(<<@version, 13, 0>>)
  end
end
