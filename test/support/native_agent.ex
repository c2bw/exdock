defmodule Exdock.TestSupport.NativeAgent do
  use NodeWire.Handler
  def init(test), do: {:ok, test}

  def handshake_data(_, test),
    do:
      {:ok,
       %{
         "node" => "node-a",
         "auth_token" => :crypto.hash(:sha256, "recovery-auth") |> Base.encode16(),
         "agent_version" => Exdock.Protocol.Compatibility.agent_version()
       }, test}

  def validate_message(_, p, _, _), do: {:ok, p}

  def handle_message({:runtime_bundle, bundle}, _, test) do
    ready = %{
      "bundle_version" => bundle["version"],
      "digest" => bundle["digest"],
      "metadata" => %{
        "platform" => "linux/amd64",
        "agent_version" => "1.1.0",
        "elixir_version" => "1.20.2",
        "otp_release" => "29"
      }
    }

    {:noreply, test, [{:send, {:ready, ready}}, {:phase, :ready}]}
  end

  def handle_message({:command, command}, _, test) do
    send(test, {:command_accepted, command})
    {:noreply, test}
  end
end
