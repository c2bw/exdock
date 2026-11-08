defmodule ExdockWeb.UserSessionControllerTest do
  use ExdockWeb.ConnCase

  alias ExdockWeb.LoginRateLimiter

  setup %{conn: conn} do
    source = conn.remote_ip
    :ok = LoginRateLimiter.reset(source)
    on_exit(fn -> LoginRateLimiter.reset(source) end)
    :ok
  end

  test "renders the shared login foundation", %{conn: conn} do
    document =
      conn
      |> get(~p"/users/log_in")
      |> html_response(200)
      |> LazyHTML.from_document()

    assert LazyHTML.filter(document, "#app-navbar") != []
    assert LazyHTML.filter(document, "#theme-toggle[phx-hook='DarkThemeToggle']") != []
    assert LazyHTML.filter(document, "#theme-system[data-theme-option='system']") != []
    assert LazyHTML.filter(document, "#theme-light[data-theme-option='light']") != []
    assert LazyHTML.filter(document, "#theme-dark[data-theme-option='dark']") != []
    assert LazyHTML.filter(document, "#login-page #login-form") != []
  end

  test "rejects attempts after the source reaches the generous limit", %{conn: conn} do
    max_attempts = login_rate_limit(:max_attempts)

    Enum.each(1..max_attempts, fn _attempt ->
      assert :ok = LoginRateLimiter.consume(conn.remote_ip)
    end)

    conn =
      post(conn, ~p"/users/log_in", %{
        "user" => %{"email" => "unknown@example.com", "password" => "incorrect"}
      })

    assert html_response(conn, 429)
    assert [_retry_after] = get_resp_header(conn, "retry-after")
  end

  test "successful login clears the source's attempt window", %{conn: conn} do
    max_attempts = login_rate_limit(:max_attempts)
    user = ExdockWeb.LiveCase.insert_user()

    Enum.each(1..(max_attempts - 1), fn _attempt ->
      assert :ok = LoginRateLimiter.consume(conn.remote_ip)
    end)

    conn =
      post(conn, ~p"/users/log_in", %{
        "user" => %{"email" => user.email, "password" => "password"}
      })

    assert redirected_to(conn) == ~p"/"
    assert :ok = LoginRateLimiter.consume(conn.remote_ip)
  end

  test "logout clears the authenticated session and redirects home", %{conn: conn} do
    user = ExdockWeb.LiveCase.insert_user()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> ExdockWeb.LiveCase.log_in_user(user)
      |> delete(~p"/users/log_out")

    assert redirected_to(conn) == ~p"/"
    assert get_session(conn, :user_token) == nil
    assert get_session(conn, :live_socket_id) == nil
  end

  test "rejects malformed login payloads without crashing", %{conn: conn} do
    conn = post(conn, ~p"/users/log_in", %{"user" => %{"email" => "missing-password@example.com"}})

    document =
      conn
      |> html_response(400)
      |> LazyHTML.from_document()

    assert LazyHTML.filter(document, "#login-form") != []
    assert LazyHTML.filter(document, "#login-form .text-error-two") != []
  end

  defp login_rate_limit(key) do
    :exdock
    |> Application.fetch_env!(:login_rate_limit)
    |> Keyword.fetch!(key)
  end
end
