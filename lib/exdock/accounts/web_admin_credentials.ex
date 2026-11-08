defmodule Exdock.Accounts.WebAdminCredentials do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Multi
  alias Exdock.Accounts.{SessionBroadcaster, User}
  alias Exdock.Repo

  require Logger

  @spec set(String.t(), String.t()) ::
          {:ok, User.t() | :no_change} | {:error, term()}
  def set(email, plain_password) do
    case Repo.get_by(User, email: email) do
      nil ->
        Logger.info("No user found matching wanted email: #{email}, setting the new user as Web Admin")
        replace_admin_and_revoke_sessions(email, plain_password)

      %User{} = user ->
        update_existing_admin(user, plain_password)
    end
  end

  defp update_existing_admin(%User{} = user, plain_password) do
    changeset = User.password_changeset(user, %{password: plain_password}, hash_password: true)

    cond do
      not changeset.valid? -> {:error, changeset.errors}
      User.valid_password?(changeset.data, plain_password) -> {:ok, :no_change}
      true -> update_password_and_revoke_sessions(user, changeset)
    end
  end

  defp replace_admin_and_revoke_sessions(email, plain_password) do
    new_admin_changeset =
      User.registration_changeset(%User{}, %{
        email: email,
        password: plain_password
      })

    Multi.new()
    |> Multi.all(:session_tokens, all_session_tokens_query())
    |> Multi.delete_all(:previous_admins, User)
    |> Multi.insert(:user, new_admin_changeset)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: new_admin, previous_admins: {removed_count, _}, session_tokens: tokens}} ->
        if removed_count > 0, do: Logger.info("Previous Web Admin was successfully removed")
        disconnect_sessions(tokens)
        {:ok, new_admin}

      {:error, _operation, reason, _changes} ->
        {:error, reason}
    end
  end

  defp update_password_and_revoke_sessions(%User{} = user, changeset) do
    Multi.new()
    |> Multi.update(:user, changeset)
    |> Multi.all(:session_tokens, user_session_tokens_query(user.id))
    |> Multi.delete_all(:sessions, user_sessions_query(user.id))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: updated_user, session_tokens: tokens}} ->
        disconnect_sessions(tokens)
        {:ok, updated_user}

      {:error, _operation, reason, _changes} ->
        {:error, reason}
    end
  end

  defp all_session_tokens_query do
    from token in "users_tokens",
      where: token.context == "session",
      select: token.token
  end

  defp user_session_tokens_query(user_id) do
    from token in "users_tokens",
      where: token.user_id == ^user_id and token.context == "session",
      select: token.token
  end

  defp user_sessions_query(user_id) do
    from token in "users_tokens",
      where: token.user_id == ^user_id and token.context == "session"
  end

  defp disconnect_sessions(tokens), do: SessionBroadcaster.disconnect_all(tokens)
end
