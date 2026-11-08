defmodule ExdockWeb.FormatTest do
  use ExUnit.Case, async: true

  alias ExdockWeb.Format

  test "formats percentages with configurable precision" do
    assert Format.percentage(12.345) == "12.3%"
    assert Format.percentage(12.345, 2) == "12.35%"
  end

  test "uses a placeholder for missing values" do
    assert Format.percentage(nil) == "-"
  end
end
