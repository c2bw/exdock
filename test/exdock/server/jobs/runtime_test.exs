defmodule Exdock.Server.Jobs.RuntimeTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Jobs.Runtime

  test "rejects publisher modules that do not implement the runtime contract" do
    assert_raise ArgumentError, ~r/invalid jobs_publisher adapter/, fn ->
      Runtime.new(publisher: String)
    end
  end

  test "rejects event modules that do not implement the runtime contract" do
    assert_raise ArgumentError, ~r/invalid event_sink adapter/, fn ->
      Runtime.new(events: String)
    end
  end
end
