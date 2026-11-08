defmodule Exdock.SizeTest do
  use ExUnit.Case, async: true

  alias Exdock.Size

  test "returns '-' for nil and negative values" do
    assert Size.human_readable(nil) == "-"
    assert Size.human_readable(-42) == "-"
  end

  test "renders values in the default human-readable format" do
    assert Size.human_readable(999) == "999.0 B"
    assert Size.human_readable(1_024) == "1.0 KB"
  end

  test "respects binary and spacing options" do
    assert Size.human_readable(1_024, binary_units: true, no_space: true) == "1.0KiB"
    assert Size.human_readable(1_024, no_unit: true, no_space: true) == "1.0"
  end

  test "supports decimal and time-unit formatting" do
    assert Size.human_readable(1_024 * 1_024 * 1_024, decimals: 2, increase_decimals: 0) == "1.07 GB"
    assert Size.human_readable(1_024, time_unit: "/s") == "1.0 KB/s"
  end

  test "trims zero decimal values when requested" do
    assert Size.human_readable(1_024, binary_units: true, decimals: 4, truncate_zero_decimals: true) == "1 KiB"
  end

  test "normalizes two values to the same unit" do
    assert Size.normalized_bytes(1_536, 512) == {"1.5", "0.5", "KB"}
  end

  test "normalizes bytes with binary and time-unit unit labels" do
    assert Size.normalized_bytes(1_024, 1_536, binary_units: true, time_unit: "/s") == {"1.0", "1.5", "KiB/s"}
  end

  test "returns placeholders for missing normalized values" do
    assert Size.normalized_bytes(nil, 1_024) == {"-", "-", ""}
  end
end
