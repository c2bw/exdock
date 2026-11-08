defmodule Exdock.Container.PolicyTest do
  use ExUnit.Case, async: true

  alias Exdock.Container.Policy

  test "protects Exdock containers from recreation" do
    refute Policy.recreatable?("Exdock")
    refute Policy.recreatable?("Exdock-agent")
    refute Policy.recreatable?("exdock-server-1")
    refute Policy.recreatable?("exdock-client-1")
    refute Policy.recreatable?("EXDOCK")
  end

  test "protects explicitly labelled containers regardless of their name" do
    refute Policy.recreatable?("server", %{configuration: %{labels: %{"exdock.protected" => "true"}}})
    assert Policy.recreatable?("worker", %{configuration: %{labels: %{"exdock.protected" => "false"}}})
    assert Policy.recreatable?("worker", %{configuration: nil})
  end

  test "allows other containers to be recreated" do
    assert Policy.recreatable?("media-server")
  end

  test "accepts only supported priorities" do
    assert Policy.valid_priority?(1)
    assert Policy.valid_priority?(5)
    refute Policy.valid_priority?(0)
    refute Policy.valid_priority?(6)
    refute Policy.valid_priority?("3")
  end

  test "accepts only supported automation thresholds" do
    assert Policy.valid_update_threshold?(0)
    assert Policy.valid_update_threshold?(4)
    refute Policy.valid_update_threshold?(-1)
    refute Policy.valid_update_threshold?(5)
    refute Policy.valid_update_threshold?("3")
  end
end
