defmodule ExdockWeb.RouterTest do
  use ExdockWeb.ConnCase, async: true

  test "API pipeline accepts JSON requests", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> ExdockWeb.Router.api([])

    assert conn.private.phoenix_format == "json"
  end
end
