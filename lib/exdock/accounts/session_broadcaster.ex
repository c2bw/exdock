defmodule Exdock.Accounts.SessionBroadcaster do
  @moduledoc """
  Transport-neutral account boundary for disconnecting authenticated sessions.

  The accounts context publishes the standard Phoenix socket broadcast through
  the application PubSub without depending on the web endpoint module.
  """

  alias Phoenix.Socket.Broadcast

  @spec disconnect_all([binary()]) :: :ok
  def disconnect_all(tokens) when is_list(tokens) do
    Enum.each(tokens, &disconnect/1)
    :ok
  end

  @spec disconnect(binary()) :: :ok
  def disconnect(token) when is_binary(token) do
    topic = "users_sessions:#{Base.url_encode64(token)}"

    Phoenix.PubSub.broadcast(
      Exdock.PubSub,
      topic,
      %Broadcast{topic: topic, event: "disconnect", payload: %{}}
    )
  end
end
