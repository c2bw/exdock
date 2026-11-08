defmodule Exdock.Server.Connection.Handler.FrameRouterTest do
  use ExUnit.Case, async: true

  alias Exdock.Protocol.Contract
  alias Exdock.Server.Connection.Handler.FrameRouter
  alias Exdock.Server.Connection.Session

  test "routes an untrusted hello to authentication" do
    hello = %{"agent_version" => "1.1.0", "auth_token" => "token", "node" => "node-a"}
    frame = Contract.encode_term_frame(:hello, hello)

    assert {:authenticate, "1.1.0", "token", "node-a"} =
             FrameRouter.route(Session.new(), frame)
  end

  test "rejects client payload frames before authentication" do
    frame = Contract.encode_term_frame(:result, %{})

    assert {:stop, :malformed_message} = FrameRouter.route(Session.new(), frame)
  end
end
