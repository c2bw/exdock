defmodule Exdock.Protocol.NodeWire do
  @moduledoc "Agent application messages carried by a NodeWire session."

  use NodeWire.Protocol, id: 0x4558444F, version: 5, max_payload_bytes: 8_388_608

  message :hello, id: 10 do
    field(:agent_version, :string, required: true)
    field(:auth_token, :string, required: true)
    field(:node, :string, required: true)
  end

  message :runtime_bundle, id: 11 do
    field(:version, :string, required: true)
    field(:digest, :string, required: true)
    field(:modules, {:map, :bytes}, required: true, max_entries: 4)
  end

  message :ready, id: 12 do
    field(:bundle_version, :string, required: true)
    field(:digest, :string, required: true)
    field(:metadata, {:map, :json}, required: true)
  end

  message :command, id: 13 do
    field(:id, :string, required: true)
    field(:kind, :string, required: true)
    field(:args, {:list, :json}, required: true)
  end

  message :progress, id: 14 do
    field(:id, :string, required: true)
    field(:kind, :string, required: true)
    field(:node, :string, required: true)
    field(:data, :json, required: true, nullable: true)
  end

  message :result, id: 15 do
    field(:id, :string, required: true)
    field(:kind, :string, required: true)
    field(:node, :string, required: true)
    field(:data, :json, required: true, nullable: true)
    field(:error, :json, required: true, nullable: true)
  end

  message :resource_sample, id: 16 do
    field(:node, :string, required: true)
    field(:container_id, :string, required: true)
    field(:sample, :json, required: true, nullable: true)
  end

  message :error, id: 9 do
    field(:reason, :string, required: true)
    field(:requirement, :string)
  end
end
