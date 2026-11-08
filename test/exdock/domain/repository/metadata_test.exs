defmodule Exdock.Domain.Repository.MetadataTest do
  use Exdock.DataCase, async: false

  alias Exdock.Server.State.Storage.Persistence.Repository, as: RepositoryPersistence
  alias Exdock.Domain.Repository.Metadata

  @url "https://github.com/openai/example"

  test "last check timestamps are truncated for utc_datetime persistence" do
    metadata = Metadata.default()
    precise = ~U[2026-06-30 15:43:22.123456Z]

    assert %Metadata{last_check: truncated} = Metadata.set_last_check(metadata, precise)
    assert truncated == ~U[2026-06-30 15:43:22Z]
    assert truncated.microsecond == {0, 0}
  end

  test "insert/2 and load/1 round-trip repository metadata" do
    metadata =
      Metadata.default()
      |> Metadata.set_state(:rate_limit)
      |> Metadata.set_last_check(~U[2026-06-30 15:43:22.123456Z])

    assert {:ok, _stored} = RepositoryPersistence.insert_metadata(metadata, @url)

    assert %Metadata{
             state: :rate_limit,
             last_check: ~U[2026-06-30 15:43:22Z]
           } = RepositoryPersistence.load_metadata(@url)
  end

  test "set_state/2 accepts every supported release page state" do
    for state <- [:ok, :not_found, :rate_limit, :unsupported, :error] do
      assert %Metadata{state: ^state} =
               Metadata.default()
               |> Metadata.set_state(state)
    end
  end

  test "set_state/2 rejects unknown release page states" do
    assert_raise FunctionClauseError, fn ->
      apply(Metadata, :set_state, [Metadata.default(), :unknown])
    end
  end

  test "load_all/0 returns stored rows as runtime metadata" do
    assert {:ok, _stored} =
             Metadata.default()
             |> Metadata.set_state(:ok)
             |> Metadata.set_last_check(~U[2026-06-30 15:43:22Z])
             |> RepositoryPersistence.insert_metadata(@url)

    assert {:ok, _stored} =
             Metadata.default()
             |> Metadata.set_state(:unsupported)
             |> Metadata.set_last_check(~U[2026-07-01 10:00:00Z])
             |> RepositoryPersistence.insert_metadata("https://github.com/openai/other")

    assert RepositoryPersistence.load_all_metadata() |> Enum.map(& &1.state) |> Enum.sort() ==
             [:ok, :unsupported]
  end

  test "load/1 returns nil for unknown repository URLs" do
    assert RepositoryPersistence.load_metadata(@url) == nil
  end
end
