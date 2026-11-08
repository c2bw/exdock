defmodule Exdock.Runtime.CommandTest do
  use ExUnit.Case, async: true

  alias Exdock.Runtime.{Command, Coordinator, Mutation}
  alias Exdock.Runtime.Mutation.Payload.UserSetting
  alias Exdock.Server.State

  test "unsupported commands return an explicit error" do
    assert Command.execute(%State{}, {:unknown, :command}) ==
             {:error, {:unsupported_command, {:unknown, :command}}}
  end

  test "coordinator commands can target an isolated mailbox" do
    assert :ok = Coordinator.command(nil, {:probe, :command}, server: self())

    assert_receive {:"$gen_cast", {:command, nil, {:probe, :command}, []}}

    assert :ok = Coordinator.node_is_down("node-a", self())
    assert_receive {:"$gen_cast", {:node_is_down, "node-a"}}
  end

  test "public submissions fail when the coordinator is unavailable" do
    operation_id = Ecto.UUID.generate()

    assert {:error, {:runtime_unavailable, :not_found}} =
             Coordinator.submit(operation_id, {:probe, :command},
               server: :missing_runtime_coordinator,
               operation_kind: :probe
             )
  end

  test "public submissions classify admission timeouts separately" do
    operation_id = Ecto.UUID.generate()

    server =
      spawn(fn ->
        receive do
          {:"$gen_call", _from, _message} -> receive do: (:stop -> :ok)
        end
      end)

    on_exit(fn -> send(server, :stop) end)

    assert {:error, {:runtime_unavailable, :timeout}} =
             Coordinator.submit(operation_id, {:probe, :command},
               server: server,
               admission_timeout: 0,
               operation_kind: :probe
             )
  end

  test "invalid mutation domains return an explicit error" do
    assert Mutation.build(:unknown, :action, nil) == {:error, {:unknown_state_domain, :unknown}}
  end

  test "invalid mutation actions return an explicit error" do
    assert Mutation.build(:settings, "action", nil) == {:error, {:invalid_mutation_action, "action"}}

    assert Mutation.build(:settings, :delete_lock, nil) ==
             {:error, {:unknown_state_action, :settings, :delete_lock}}
  end

  test "mutation construction rejects malformed payload shapes" do
    assert Mutation.build(:containers, :priority, {:"not-a-node"}) ==
             {:error, {:invalid_mutation_payload, :containers, :priority}}

    assert Mutation.image_delete_lock("node", "image", :locked) ==
             {:error, {:invalid_mutation_payload, :images, :delete_lock}}
  end

  test "user setting constructors return validation errors" do
    assert Mutation.user_setting(:unknown, true) == {:error, {:unknown_user_setting, :unknown}}

    assert Mutation.user_setting(:container_resources, :sometimes) ==
             {:error, {:invalid_user_setting_value, :container_resources}}
  end

  test "typed constructors normalize settings before building mutations" do
    assert {:ok,
            %Mutation{
              domain: :settings,
              action: :user_setting,
              data: %UserSetting{key: :container_resources, value: true}
            }} = Mutation.user_setting("container_resources", "true")
  end

  test "typed constructors reject malformed collection members" do
    assert Mutation.container_logs("node", "container", ["valid", :invalid], DateTime.utc_now()) ==
             {:error, {:invalid_mutation_payload, :containers, :set_logs}}

    assert Mutation.repository_releases([{:ok, "https://example.com/repo", [:invalid]}]) ==
             {:error, {:invalid_mutation_payload, :repositories, :repository_releases}}
  end

  test "node setting constructors return validation errors" do
    assert Mutation.node_setting("node", :unknown, "value") ==
             {:error, {:unknown_node_setting, :unknown}}

    assert Mutation.node_setting("node", :web_ui, 123) ==
             {:error, {:invalid_node_setting_value, :web_ui}}
  end
end
