defmodule Exdock.Database.PersistedPayloadTest do
  use ExUnit.Case, async: true

  alias Exdock.Database.PersistedPayload

  test "round-trips Base64-wrapped compressed JSON" do
    payload = %{"hostname" => "example", "ports" => [4000, 4001]}

    assert {:ok, encoded} = PersistedPayload.encode(payload)
    assert {:ok, ^payload} = PersistedPayload.decode(encoded)
  end

  test "decodes the legacy raw-gzip representation" do
    payload = %{"status" => "running"}
    raw_payload = payload |> Jason.encode!() |> :zlib.gzip()

    assert {:ok, ^payload} = PersistedPayload.decode(raw_payload)
  end

  test "returns tagged errors for malformed payloads" do
    assert {:error, {:gunzip_failed, _message}} =
             PersistedPayload.decode("not-a-compressed-payload")
  end
end
