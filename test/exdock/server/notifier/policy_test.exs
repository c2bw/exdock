defmodule Exdock.Server.Notifier.PolicyTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Notifier.Policy

  test "initialization describes handler work without performing it" do
    assert {:disabled, nil, []} = Policy.initialize(nil)

    assert {:enabled, "https://loki.example", [:configure_handler]} =
             Policy.initialize("https://loki.example")

    assert [{:verify_connectivity, "https://loki.example"}] =
             Policy.continued(:enabled, "https://loki.example")
  end

  test "notification decisions are pure effects gated by status" do
    payload = %{node: "node", name: "app", priority: 2, old: :stopped, new: :running}

    assert [] = Policy.notification(:disabled, :container_status, payload)

    assert [{:notification_log, :info, :container_status, message}] =
             Policy.notification(:enabled, :container_status, payload)

    assert is_binary(message)
    assert message =~ "app"
  end

  test "termination only removes a configured handler" do
    assert [{:system_log, :debug, _message}] = Policy.terminate(:disabled, :shutdown)

    assert [{:system_log, :debug, _message}, :remove_handler] =
             Policy.terminate(:enabled, :shutdown)
  end
end
