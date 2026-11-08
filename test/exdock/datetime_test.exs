defmodule Exdock.DatetimeTest do
  use ExUnit.Case, async: true

  alias Exdock.Datetime
  alias Exdock.Datetime.Format
  alias Exdock.Datetime.Staleness
  alias Exdock.ReadModel.Node, as: NodeReadModel
  alias Exdock.Domain.Node

  @fetched_at ~U[2026-01-01 12:00:00Z]

  test "returns last fetch time from string-keyed node map" do
    nodes = %{"node_a" => %Node{node: "node_a", fetched_at: @fetched_at}}

    assert Datetime.get_node_last_fetch(nodes, "node_a") == @fetched_at
    assert NodeReadModel.last_fetch(nodes, "node_a") == @fetched_at
  end

  test "returns nil when node is not found" do
    assert Datetime.get_node_last_fetch(%{}, "missing_node") == nil
  end

  test "elapsed_since formats compact duration parts" do
    since = ~U[2026-01-02 14:03:04Z]
    datetime = ~U[2026-01-01 12:00:00Z]

    assert Datetime.elapsed_since(datetime, since) == "1d 2h 3m 4s"
  end

  test "elapsed_since accepts ISO strings" do
    since = ~U[2026-01-01 12:01:05Z]

    assert Datetime.elapsed_since("2026-01-01T12:00:00Z", since) == "1m 5s"
  end

  test "elapsed_since returns an empty string for nil or invalid strings" do
    since = ~U[2026-01-01 12:00:00Z]

    assert Datetime.elapsed_since(nil, since) == ""
    assert Datetime.elapsed_since("not a datetime", since) == ""
  end

  test "elapsed_since clamps future datetimes to one second" do
    since = ~U[2026-01-01 12:00:00Z]
    future = ~U[2026-01-01 12:10:00Z]

    assert Datetime.elapsed_since(future, since) == "1s"
  end

  test "duration_until accepts an explicit clock" do
    now = ~U[2026-01-01 20:00:00Z]

    assert Datetime.duration_until(~U[2026-01-01 22:30:00Z], now) == "2h 30m"
  end

  test "simple_diff uses the requested stop unit" do
    timestamp = ~U[2026-01-01 12:00:00Z]
    reference = ~U[2026-01-01 12:10:00Z]

    assert Datetime.simple_diff(timestamp, reference, :minute) == "10m"
    assert Datetime.simple_diff(timestamp, reference, :hour) == "0h"
  end

  test "simple_diff falls back to the next smaller unit when intermediate units are zero" do
    timestamp = ~U[2026-01-01 12:00:00Z]
    reference = ~U[2026-01-01 12:59:00Z]

    assert Datetime.simple_diff(timestamp, reference, :minute) == "59m"
  end

  test "staleness classification has deterministic threshold boundaries" do
    now = ~U[2026-01-01 12:00:00Z]

    assert Staleness.classify(nil, now) == nil
    assert Staleness.classify(DateTime.add(now, -299, :second), now) == :fresh
    assert Staleness.classify(DateTime.add(now, -300, :second), now) == :stale
    assert Staleness.classify(DateTime.add(now, -12, :hour), now) == :stale
    assert Staleness.classify(DateTime.add(now, -43_201, :second), now) == :old
  end

  test "format parses ISO datetimes and rejects invalid values" do
    assert Format.from_string("2026-01-01T12:00:00Z") == @fetched_at
    assert Format.from_string("not a datetime") == nil
    assert Format.maybe_datetime!(@fetched_at) == @fetched_at
    assert_raise ArgumentError, ~r/Invalid datetime string/, fn -> Format.maybe_datetime!("invalid") end
  end

  test "format serializes at the requested precision" do
    datetime = ~U[2026-01-01 12:00:00.123456Z]

    assert Format.prettify(datetime) == "2026-01-01 12:00:00"
    assert Format.prettify(datetime, :millisecond) == "2026-01-01 12:00:00.123"
    assert Format.as_string(datetime, "Etc/UTC") == "2026-01-01 12:00:00"
    assert Format.as_string(nil, "Etc/UTC") == nil
  end

  test "timezone conversion falls back to the original datetime when the zone is invalid" do
    assert Format.utc_to_timezone(@fetched_at, "Invalid/Timezone") == @fetched_at
  end

  test "unix_epoch returns the UTC epoch" do
    assert Datetime.unix_epoch() == ~U[1970-01-01 00:00:00Z]
  end
end
