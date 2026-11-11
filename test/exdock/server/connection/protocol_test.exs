defmodule Exdock.Server.Connection.ProtocolTest do
  use ExUnit.Case, async: true

  alias Exdock.Protocol.{Contract, Message}
  alias Exdock.Server.Connection.Protocol
  alias Exdock.Server.Connection.WireMessage
  alias Exdock.AgentRuntime.Wire

  @metadata %{
    "platform" => "linux/amd64",
    "agent_version" => "1.2.0",
    "elixir_version" => "1.18.4",
    "otp_release" => "27"
  }

  test "round trips heartbeat and server error frames" do
    assert {:error, :shutdown} = Protocol.decode_message(Protocol.encode_message({:error, :shutdown}))
  end

  test "decodes a validated unauthenticated hello" do
    hello = %{"agent_version" => "1.2.3", "auth_token" => "abc", "node" => "node-01"}
    frame = Contract.encode!(:hello, hello)

    assert {:hello, "1.2.3", "abc", "node-01"} = Protocol.decode_message(frame)
  end

  test "encodes only validated protocol commands" do
    command = Message.command("job-id", :container_start, ["container-id"])
    assert {:ok, {:command, payload}} = Protocol.encode_message({:command, command}) |> Contract.decode()

    assert {:ok, %{"id" => "job-id", "kind" => "container_start", "args" => ["container-id"]}} =
             {:ok, payload}

    assert_raise ArgumentError, fn ->
      Protocol.encode_message({:command, %{"id" => "job-id", "kind" => "arbitrary_rpc", "args" => []}})
    end
  end

  test "converts authenticated result maps at the transport boundary" do
    payload = Message.result("job-id", "container_start", "node", "container-id", nil)
    frame = Contract.encode!(:result, payload)

    assert {:client_message,
            %WireMessage{
              type: :result,
              id: "job-id",
              kind: "container_start",
              node: "node",
              data: "container-id",
              error: nil
            }} = Protocol.decode_message(frame, :authenticated)
  end

  test "round trips protocol-owned node refresh snapshot maps" do
    container = %Exdock.Protocol.Snapshot.Container{
      name: "web",
      id: "container-id",
      is_running: true,
      stack_name: "app",
      image_tag: "example/web:latest",
      image_id: "sha256:image",
      inspect: %DockerEngineAPI.Model.ContainerInspectResponse{
        State: %DockerEngineAPI.Model.ContainerState{Status: "running", Running: true}
      }
    }

    image = %Exdock.Protocol.Snapshot.Image{
      id: "sha256:image",
      name: "example/web",
      tags: ["example/web:latest"],
      digest: "sha256:digest",
      size: 10,
      shared_size: 2,
      build_date: ~U[2026-07-22 10:00:00Z]
    }

    data = Wire.encode_result("node_refresh", {%{ok: [container], errored: []}, %{ok: [image], errored: []}})
    frame = Contract.encode!(:result, Message.result("refresh-id", "node_refresh", "node", data, nil))

    assert {:client_message,
            %WireMessage{
              type: :result,
              data:
                {%{
                   ok: [
                     %Exdock.Protocol.Snapshot.Container{
                       name: "web",
                       inspect: %{"State" => %{"Status" => "running", "Running" => true}}
                     }
                   ]
                 }, %{ok: [%Exdock.Protocol.Snapshot.Image{build_date: ~U[2026-07-22 10:00:00Z]}]}}
            }} = Protocol.decode_message(frame, :authenticated)
  end

  test "rejects malformed node refresh result maps" do
    payload = Message.result("refresh-id", "node_refresh", "node", %{"containers" => []}, nil)

    assert {:error, :malformed_message} =
             Protocol.decode_event({:result, payload}, :authenticated)

    malformed_snapshot = %{
      "containers" => %{"ok" => [%{}], "errored" => []},
      "images" => %{"ok" => [], "errored" => []}
    }

    payload = Message.result("refresh-id", "node_refresh", "node", malformed_snapshot, nil)

    assert {:error, :malformed_message} =
             Protocol.decode_message(Contract.encode!(:result, payload), :authenticated)
  end

  test "converts authenticated progress and resource maps" do
    progress = Message.progress("job-id", "container_restart", "node", "starting")

    assert {:client_message,
            %WireMessage{
              type: :progress,
              id: "job-id",
              kind: "container_restart",
              node: "node",
              data: "starting"
            }} =
             Protocol.decode_message(Contract.encode!(:progress, progress), :authenticated)

    sample = Message.resource_sample("node", "container-id", %{read: 1})

    assert {:client_message, %WireMessage{type: :resource_sample, node: "node", id: "container-id", data: %{"read" => 1}}} =
             Protocol.decode_message(Contract.encode!(:resource_sample, sample), :authenticated)
  end

  test "rejects lifecycle and result messages at the wrong trust boundary" do
    result = Message.result("job-id", "container_start", "node", "container-id", nil)
    assert {:error, :malformed_message} = Protocol.decode_message(Contract.encode!(:result, result))

    ready = %{"bundle_version" => "1", "digest" => "abc", "metadata" => @metadata}
    assert {:error, :malformed_message} = Protocol.decode_message(Contract.encode!(:ready, ready))

    assert {:ready, "1", "abc", @metadata} =
             Protocol.decode_message(Contract.encode!(:ready, ready), :authenticated)
  end

  test "rejects invalid authenticated node identifiers without raising" do
    progress = Message.progress("job-id", "container_restart", "bad node!", "starting")
    result = Message.result("job-id", "container_start", "local", "container-id", nil)
    sample = Message.resource_sample("", "container-id", %{read: 1})

    for {message_type, payload} <- [
          {:progress, progress},
          {:result, result},
          {:resource_sample, sample}
        ] do
      frame = Contract.encode!(message_type, payload)
      assert {:error, :malformed_message} = Protocol.decode_message(frame, :authenticated)
    end
  end

  test "validates and sanitizes ready metadata" do
    ready = %{
      "bundle_version" => "1",
      "digest" => "abc",
      "metadata" => Map.put(@metadata, "future", %{ignored: true})
    }

    assert {:ready, "1", "abc", @metadata} =
             Protocol.decode_message(Contract.encode!(:ready, ready), :authenticated)

    for metadata <- [
          Map.delete(@metadata, "platform"),
          Map.put(@metadata, "platform", ""),
          Map.put(@metadata, "otp_release", 27),
          Map.put(@metadata, "platform", String.duplicate("x", 129))
        ] do
      invalid_ready = %{"bundle_version" => "1", "digest" => "abc", "metadata" => metadata}

      assert {:error, :malformed_message} =
               Protocol.decode_message(Contract.encode!(:ready, invalid_ready), :authenticated)
    end

    assert {:error, %NodeWire.Error{}} =
             Exdock.Protocol.NodeWire.encode(:ready, %{"bundle_version" => "1", "digest" => "abc"})
  end

  test "rejects malformed maps and unsafe atom payloads" do
    assert {:error, %NodeWire.Error{}} = Exdock.Protocol.NodeWire.encode(:result, %{"id" => "missing-fields"})

    atom_name = "untrusted_protocol_atom_#{System.unique_integer([:positive])}"
    atom_payload = <<131, 118, byte_size(atom_name)::16, atom_name::binary>>
    frame = <<4, 10, atom_payload::binary>>

    assert_raise ArgumentError, fn -> String.to_existing_atom(atom_name) end
    assert {:error, :malformed_message} = Protocol.decode_message(frame)
    assert_raise ArgumentError, fn -> String.to_existing_atom(atom_name) end
  end

  test "rejects malformed and incompatible frames" do
    assert {:error, :malformed_message} = Protocol.decode_message(<<4>>)
    assert {:error, :malformed_message} = Protocol.decode_message(<<3, 1>>)
    assert {:error, :malformed_message} = Protocol.decode_message(<<5, 1>>)
    assert {:error, :malformed_message} = Protocol.decode_message(<<4, 255>>)
  end
end
