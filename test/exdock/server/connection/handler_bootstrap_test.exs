defmodule Exdock.Server.Connection.Handler.BootstrapTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Connection.Handler.Bootstrap
  alias Exdock.Server.Connection.Handler.State
  alias Exdock.Server.Connection.RuntimeBundleProvider
  alias Exdock.Server.Connection.Session

  test "authenticates, registers, and offers one runtime bundle" do
    test_pid = self()
    bundle = %{"digest" => "bundle-digest"}

    register = fn client_name, handler ->
      send(test_pid, {:registered, client_name, handler})
      :ok
    end

    assert {:ok, state, ^bundle} =
             Bootstrap.authenticate(handler_state(), "1.3.0", "token", "node-a",
               register: register,
               build_bundle: fn -> {:ok, bundle} end
             )

    assert_receive {:registered, "node-a", handler}
    assert handler == self()
    assert state.session.phase == :awaiting_ready
    assert state.session.bundle_digest == "bundle-digest"
    assert Session.registered?(state.session)
  end

  test "rejects credentials before registration" do
    register = fn _client_name, _handler ->
      flunk("invalid credentials must not register a client")
    end

    assert {:error, :invalid_auth, state} =
             Bootstrap.authenticate(handler_state(), "1.3.0", "wrong-token", "node-a", register: register)

    assert state.session.client_name == "node-a"
    refute Session.registered?(state.session)
  end

  test "keeps successful registration visible when bundle construction fails" do
    assert {:error, :load_module_fail, state} =
             Bootstrap.authenticate(handler_state(), "1.3.0", "token", "node-a",
               register: fn _client_name, _handler -> :ok end,
               build_bundle: fn -> {:error, :load_module_fail} end
             )

    assert Session.registered?(state.session)
  end

  test "initializes only the exact offered runtime bundle" do
    session =
      Session.new()
      |> Session.identify("node-a")
      |> Session.authenticate()
      |> Session.offer_bundle("bundle-digest")

    state = %{handler_state() | session: session}
    version = RuntimeBundleProvider.version()

    assert {:ok, initialized} = Bootstrap.initialize(state, version, "bundle-digest")
    assert Session.ready?(initialized.session)

    assert {:error, :runtime_bundle_mismatch, ^state} =
             Bootstrap.initialize(state, version, "wrong-digest")
  end

  defp handler_state do
    %State{
      parent_pid: self(),
      auth_key: "token",
      session: Session.new()
    }
  end
end
