defmodule Exdock.Container.AutomationPolicyTest do
  use ExUnit.Case, async: true

  alias Exdock.Container.AutomationPolicy

  test "explicit policies override the priority threshold" do
    refute AutomationPolicy.participates?(5, :disabled, 1)
    assert AutomationPolicy.participates?(1, :enabled, 5)
  end

  test "passthrough participates only above the threshold" do
    refute AutomationPolicy.participates?(2, :passthrough, 2)
    assert AutomationPolicy.participates?(3, :passthrough, 2)
  end

  test "eligibility also requires a running outdated container" do
    assert AutomationPolicy.eligible?(3, :passthrough, 2, true, :outdated)
    refute AutomationPolicy.eligible?(3, :passthrough, 2, false, :outdated)
    refute AutomationPolicy.eligible?(3, :passthrough, 2, true, :updated)
  end
end
