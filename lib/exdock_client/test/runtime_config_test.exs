defmodule ExdockClient.RuntimeConfigTest do
  use ExUnit.Case, async: false

  @runtime_config Path.expand("../config/runtime.exs", __DIR__)

  setup do
    previous = System.get_env("NODEWIRE_CA_FILE")
    previous_auth = System.get_env("AUTH_KEY")
    System.put_env("AUTH_KEY", "runtime-config-test")

    on_exit(fn ->
      case previous_auth do
        nil -> System.delete_env("AUTH_KEY")
        value -> System.put_env("AUTH_KEY", value)
      end

      case previous do
        nil -> System.delete_env("NODEWIRE_CA_FILE")
        value -> System.put_env("NODEWIRE_CA_FILE", value)
      end
    end)
  end

  test "accepts the generated server certificate without a CA file" do
    System.delete_env("NODEWIRE_CA_FILE")
    assert tls_options() == [verify: :verify_none]
  end

  test "legacy CA environment settings do not change the accepted trust mode" do
    for ca <- ["", "/etc/exdock/ca.pem"] do
      System.put_env("NODEWIRE_CA_FILE", ca)
      assert tls_options() == [verify: :verify_none]
    end
  end

  defp tls_options do
    @runtime_config
    |> Config.Reader.read!(env: :prod, target: :host)
    |> Keyword.fetch!(:exdock_client)
    |> Keyword.fetch!(:agent_tls_options)
  end
end
