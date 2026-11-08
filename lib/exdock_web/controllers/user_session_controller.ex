defmodule ExdockWeb.UserSessionController do
  use ExdockWeb, :controller

  alias Exdock.Accounts
  alias ExdockWeb.ClientIp
  alias ExdockWeb.LoginRateLimiter
  alias ExdockWeb.UserAuth

  @invalid_credentials_message "Invalid email or password"

  def new(conn, _params) do
    render_new(conn, %{}, nil)
  end

  def create(conn, %{
        "user" => %{"email" => email, "password" => password} = user_params
      })
      when is_binary(email) and is_binary(password) do
    source_ip = ClientIp.from_conn(conn)

    case LoginRateLimiter.consume(source_ip) do
      :ok ->
        authenticate(conn, email, password, user_params, source_ip)

      {:error, {:rate_limited, retry_after}} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after))
        |> put_status(:too_many_requests)
        |> render_new(user_params, @invalid_credentials_message)
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> render_new(%{}, @invalid_credentials_message)
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end

  defp authenticate(conn, email, password, user_params, source_ip) do
    if user = Accounts.get_user_by_email_and_password(email, password) do
      :ok = LoginRateLimiter.reset(source_ip)

      conn
      |> put_flash(:info, "Welcome back!")
      |> UserAuth.log_in_user(user, user_params)
    else
      # Do not disclose whether the submitted email is registered.
      render_new(conn, user_params, @invalid_credentials_message)
    end
  end

  defp render_new(conn, user_params, error_message) do
    render(conn, :new,
      error_message: error_message,
      form: Phoenix.Component.to_form(user_params, as: :user)
    )
  end
end
