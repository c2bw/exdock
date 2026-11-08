defmodule ExdockWeb.PageLive.Utils.LiveOperationTest do
  use ExUnit.Case, async: true

  alias ExdockWeb.PageLive.Utils.LiveOperation

  test "successful operations leave the socket unchanged" do
    socket = %Phoenix.LiveView.Socket{}

    assert LiveOperation.handle(socket, {:ok, Ecto.UUID.generate()}) == socket
  end
end
