defmodule Exdock.Server.State.Storage.Persistence.ResultTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.State.Storage.Persistence.{Error, Result}

  test "normalizes insert and write failures without discarding their causes" do
    insert_cause = %{constraint: :unique}
    write_cause = {:sqlite, :busy}

    assert {:error, %Error{operation: :node_insert, cause: ^insert_cause}} =
             Result.normalize_insert_result({:error, insert_cause}, :node_insert)

    assert {:error, %Error{operation: :node_update, cause: ^write_cause}} =
             Result.normalize_write_result({:error, write_cause}, :node_update)
  end

  test "returns a structured not-found cause when required data is absent" do
    cause = {:not_found, :node_data, "node-a"}

    assert {:error, %Error{operation: :container_load, cause: ^cause}} =
             Result.require_loaded(nil, :container_load, cause)

    assert {:ok, :loaded} = Result.require_loaded(:loaded, :container_load, cause)
  end
end
