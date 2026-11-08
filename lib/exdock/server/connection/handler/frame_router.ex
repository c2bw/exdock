defmodule Exdock.Server.Connection.Handler.FrameRouter do
  @moduledoc """
  Decodes one client frame and selects the session-level action.

  Keeping this operation pure makes the connection process responsible only for
  transport, lifecycle, and interpreting the selected action.
  """

  alias Exdock.Server.Connection.{Protocol, Session}

  @spec route(Session.t(), binary()) :: term()
  def route(%Session{} = session, frame) when is_binary(frame) do
    frame
    |> Protocol.decode_message(Session.trust(session))
    |> then(&Session.route(session, &1))
  end
end
