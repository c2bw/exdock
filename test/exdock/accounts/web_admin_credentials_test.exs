defmodule Exdock.Accounts.WebAdminCredentialsTest do
  use Exdock.DataCase, async: false

  alias Exdock.Accounts
  alias Exdock.Accounts.User

  test "rotating the password revokes and disconnects every existing session" do
    user = insert_user("old-password")
    first_token = Accounts.generate_user_session_token(user)
    second_token = Accounts.generate_user_session_token(user)

    ExdockWeb.Endpoint.subscribe(session_topic(first_token))
    ExdockWeb.Endpoint.subscribe(session_topic(second_token))

    assert {:ok, updated_user} =
             Accounts.set_webui_login_credentials(user.email, "new-password")

    refute User.valid_password?(updated_user, "old-password")
    assert User.valid_password?(updated_user, "new-password")
    refute Accounts.get_user_by_session_token(first_token)
    refute Accounts.get_user_by_session_token(second_token)

    assert_receive %Phoenix.Socket.Broadcast{
      topic: first_topic,
      event: "disconnect",
      payload: %{}
    }

    assert first_topic == session_topic(first_token)

    assert_receive %Phoenix.Socket.Broadcast{
      topic: second_topic,
      event: "disconnect",
      payload: %{}
    }

    assert second_topic == session_topic(second_token)
  end

  test "reusing the current password preserves existing sessions" do
    user = insert_user("current-password")
    token = Accounts.generate_user_session_token(user)

    assert {:ok, :no_change} =
             Accounts.set_webui_login_credentials(user.email, "current-password")

    assert Accounts.get_user_by_session_token(token)
  end

  test "changing the admin email atomically replaces the user and disconnects existing sessions" do
    user = insert_user("old-password")
    token = Accounts.generate_user_session_token(user)
    ExdockWeb.Endpoint.subscribe(session_topic(token))

    assert {:ok, new_admin} =
             Accounts.set_webui_login_credentials("replacement@example.com", "new-password")

    refute Accounts.get_user_by_email(user.email)
    assert Accounts.get_user_by_email("replacement@example.com").id == new_admin.id
    assert User.valid_password?(new_admin, "new-password")
    refute Accounts.get_user_by_session_token(token)

    assert_receive %Phoenix.Socket.Broadcast{
      topic: topic,
      event: "disconnect",
      payload: %{}
    }

    assert topic == session_topic(token)
  end

  test "invalid replacement email preserves the current admin and sessions" do
    user = insert_user("current-password")
    token = Accounts.generate_user_session_token(user)

    assert {:error, %Ecto.Changeset{}} =
             Accounts.set_webui_login_credentials("invalid-email", "valid-password")

    assert Accounts.get_user_by_email(user.email).id == user.id
    assert Accounts.get_user_by_session_token(token).id == user.id
  end

  defp insert_user(password) do
    {:ok, user} =
      %User{}
      |> User.registration_changeset(%{
        email: "admin-#{System.unique_integer([:positive])}@example.com",
        password: password
      })
      |> Repo.insert()

    user
  end

  defp session_topic(token) do
    "users_sessions:#{Base.url_encode64(token)}"
  end
end
