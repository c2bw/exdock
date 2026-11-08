defmodule Exdock.Server.Logging.RuntimeTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Logging.Runtime

  test "rejects event modules that do not implement the runtime contract" do
    assert_raise ArgumentError, ~r/invalid event_sink adapter/, fn ->
      Runtime.new(events: String)
    end
  end

  test "rejects context providers with the wrong arity" do
    assert_raise ArgumentError, ~r/zero-arity function/, fn ->
      Runtime.new(context_provider: fn _value -> :context end)
    end
  end
end
