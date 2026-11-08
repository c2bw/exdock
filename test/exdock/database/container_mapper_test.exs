defmodule Exdock.Database.Container.MapperTest do
  use ExUnit.Case, async: true

  alias Exdock.Database.Container.Mapper
  alias Exdock.Database.Container.Record
  alias Exdock.Database.Container.Row

  test "round-trips runtime records through the stored representation" do
    record = record()

    assert {:ok, stored} = Mapper.to_row(record)
    assert stored.node == "node"
    assert is_binary(stored.configuration)
    assert is_binary(stored.state)

    assert {:ok, ^record} = stored |> then(&struct!(Row, &1)) |> Mapper.to_record()
  end

  test "reports the field and container identity for invalid persisted payloads" do
    row =
      record()
      |> Map.from_struct()
      |> Map.merge(%{configuration: "invalid", state: "invalid"})
      |> then(&struct!(Row, &1))

    assert {:error, {:invalid_container_payload, "node", "api", {:configuration, {:gunzip_failed, _message}}}} =
             Mapper.to_record(row)
  end

  defp record do
    %Record{
      node: "node",
      name: "api",
      id: "container-id",
      is_running: true,
      stack_name: "stack",
      configuration: %{"hostname" => "api"},
      state: %{"status" => "running"},
      image_tag: "repo/api:latest",
      image_id: "sha256:image",
      image_status: :updated,
      is_deleted: false
    }
  end
end
