defmodule Exdock.Protocol.AgentMetadataTest do
  use ExUnit.Case, async: true

  alias Exdock.Protocol.AgentMetadata

  @metadata %{
    "platform" => "linux/amd64",
    "agent_version" => "1.1.0",
    "elixir_version" => "1.18.4",
    "otp_release" => "27"
  }

  test "retains supported fields and ignores additive fields" do
    assert {:ok, @metadata} = AgentMetadata.sanitize(Map.put(@metadata, "future_field", %{"any" => :term}))
  end

  test "rejects missing, empty, non-string, and oversized fields" do
    for invalid <- [
          Map.delete(@metadata, "platform"),
          Map.put(@metadata, "platform", ""),
          Map.put(@metadata, "agent_version", 1),
          Map.put(@metadata, "elixir_version", String.duplicate("x", 33)),
          :not_a_map
        ] do
      assert {:error, :invalid_metadata} = AgentMetadata.sanitize(invalid)
    end
  end
end
