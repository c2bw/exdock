defmodule ExdockWeb.LiveCase do
  @moduledoc """
  Shared setup for authenticated LiveView tests.

  The UI reads from the in-memory Exdock server process on mount, so tests that
  exercise LiveViews boot that process under ExUnit supervision and log in a
  disposable user through the same session token path used by the browser.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint ExdockWeb.Endpoint

      use ExdockWeb, :verified_routes

      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import Plug.Conn
      import ExdockWeb.LiveCase
    end
  end

  setup tags do
    Exdock.DataCase.setup_sandbox(tags)
    ensure_exdock_server!()

    user = insert_user()

    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Test.init_test_session(%{})
      |> log_in_user(user)

    {:ok, conn: conn, user: user}
  end

  def log_in_user(conn, user) do
    token = Exdock.Accounts.generate_user_session_token(user)

    conn
    |> Plug.Conn.put_session(:user_token, token)
    |> Plug.Conn.put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")
  end

  def insert_user(attrs \\ %{}) do
    defaults = %{
      email: "ui-#{System.unique_integer([:positive])}@example.com",
      password: "password"
    }

    %Exdock.Accounts.User{}
    |> Exdock.Accounts.User.registration_changeset(Map.merge(defaults, attrs))
    |> Exdock.Repo.insert!()
  end

  def subscribe_to_operations! do
    :ok = Exdock.Events.subscribe(:operations)
  end

  def await_operation!(kind, timeout \\ 1_000) when is_atom(kind) do
    receive do
      {:exdock_event, :operations, _revision, %{kind: ^kind, state: :finished, result: result}} ->
        result
    after
      timeout ->
        ExUnit.Assertions.flunk("Expected #{inspect(kind)} operation to finish")
    end
  end

  def ensure_exdock_server! do
    start_named_child(Exdock.Server.Broadcast, {Exdock.Server.Broadcast, name: Exdock.Server.Broadcast})
    start_named_child(Exdock.Server.Logging, {Exdock.Server.Logging, name: Exdock.Server.Logging})
    start_named_child(Exdock.Server.Jobs, {Exdock.Server.Jobs.Supervisor, []})
    start_named_child(Exdock.Server, ExdockWeb.LiveCase.TestServer)

    :ok
  end

  defp start_named_child(name, child_spec) do
    if Process.whereis(name) == nil do
      start_supervised!(child_spec)
    end
  end
end
