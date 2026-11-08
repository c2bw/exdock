defmodule Exdock.Server.State.Storage.Persistence.BatchWriterTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.State.Storage.Persistence.BatchWriter
  alias Exdock.Server.State.Storage.Persistence.Error

  test "persist_each stops at the first rejected record" do
    owner = self()

    assert {:error, :invalid} =
             BatchWriter.persist_each([:first, :invalid, :unreached], fn record ->
               send(owner, {:persisted, record})
               if record == :invalid, do: {:error, :invalid}, else: :ok
             end)

    assert_receive {:persisted, :first}
    assert_receive {:persisted, :invalid}
    refute_receive {:persisted, :unreached}
  end

  test "insert_rows maps records and normalizes bulk errors" do
    assert {:error, %Error{operation: :image_insert_all, cause: :unavailable}} =
             BatchWriter.insert_rows(
               [1, 2],
               &(&1 * 2),
               fn rows ->
                 assert rows == [2, 4]
                 {:error, :unavailable}
               end,
               :image_insert_all
             )
  end

  test "sync_set normalizes database update results" do
    assert :ok = BatchWriter.sync_set({2, nil}, :container_set_sync)

    assert {:error, %Error{operation: :container_set_sync, cause: :database_busy}} =
             BatchWriter.sync_set({:error, :database_busy}, :container_set_sync)
  end
end
