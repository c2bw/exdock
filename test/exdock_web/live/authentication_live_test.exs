defmodule ExdockWeb.AuthenticationLiveTest do
  use ExdockWeb.LiveCase

  alias Exdock.Accounts

  test "live navigation revalidates a revoked session token", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    token = get_session(conn, :user_token)

    assert :ok = Accounts.delete_user_session_token(token)

    assert {:error, {:redirect, %{to: "/users/log_in"}}} =
             live_redirect(view, to: ~p"/images")
  end
end
