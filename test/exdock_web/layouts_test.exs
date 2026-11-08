defmodule ExdockWeb.LayoutsTest do
  use ExUnit.Case, async: true

  test "owns the Phoenix 1.8 flash group boundary" do
    assert function_exported?(ExdockWeb.Layouts, :flash_group, 1)
    refute function_exported?(ExdockWeb.CoreComponents, :flash_group, 1)
  end
end
