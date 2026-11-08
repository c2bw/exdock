defmodule Exdock.Server.State.EffectsTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.State.Effects
  alias Exdock.Server.State.Effects.Plan

  test "broadcasts include derived projections as explicit ordered effects" do
    assert Effects.broadcasts([:nodes, :images, :containers, :repositories]) == [
             {:broadcast, :nodes, nil},
             {:broadcast, :images, nil},
             {:broadcast, :containers, nil},
             {:broadcast, :repositories, nil},
             {:broadcast_projection, :cluster_info},
             {:broadcast_projection, :server_configuration}
           ]
  end

  test "derived broadcasts identify the projections invalidated by settings" do
    assert Effects.derived_broadcasts([:settings]) == [
             {:broadcast_projection, :server_configuration}
           ]
  end

  test "flattens named phases in the state transition order" do
    plan =
      Plan.new(
        cleanup: [{:log, :debug, "cleanup"}],
        publications: [{:broadcast, :nodes, nil}],
        before_publication: [{:log, :info, "before"}],
        follow_ups: [{:log, :info, "follow-up"}],
        status_changes: [{:log, :info, "status"}],
        derived_publications: [{:broadcast_projection, :server_configuration}]
      )

    assert Plan.effects(plan) == [
             {:log, :info, "before"},
             {:log, :info, "status"},
             {:broadcast, :nodes, nil},
             {:broadcast_projection, :server_configuration},
             {:log, :info, "follow-up"},
             {:log, :debug, "cleanup"}
           ]
  end

  test "rejects non-list phase values" do
    assert_raise ArgumentError, "effect phase publications must be a list", fn ->
      Plan.new(publications: :invalid)
    end
  end
end
