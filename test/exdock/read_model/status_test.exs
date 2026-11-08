defmodule Exdock.ReadModel.StatusTest do
  use ExUnit.Case, async: true

  alias Exdock.ReadModel.Status
  alias Exdock.Status.Dashboard.Row

  test "detects dashboard row errors without treating row structs as enumerables" do
    requested_status = %{
      dash: %{node_refresh: %{"node-a" => Row.new({:ok, :requested}, nil)}}
    }

    errored_status = %{
      dash: %{node_refresh: %{"node-a" => Row.new({:error, :nodedown}, nil)}}
    }

    refute Status.errors?(requested_status)
    assert Status.errors?(errored_status)
  end
end
