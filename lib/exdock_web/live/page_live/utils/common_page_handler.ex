defmodule ExdockWeb.PageLive.Utils.CommonPageHandler do
  @moduledoc """
  Composes the focused event handlers shared by server-backed LiveViews.

  Each handler owns one concern and returns either a handled socket or
  `:unhandled`, keeping the public LiveView fallback API unchanged.
  """

  alias ExdockWeb.PageLive.Utils.CommonPageHandler.{
    CommandEvents,
    SettingsEvents,
    UiEvents
  }

  @handlers [CommandEvents, SettingsEvents, UiEvents]

  @spec handle(binary(), any(), Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def handle(event, params, socket) do
    Enum.reduce_while(@handlers, socket, fn handler, socket ->
      case handler.handle(event, params, socket) do
        {:handled, socket} -> {:halt, socket}
        :unhandled -> {:cont, socket}
      end
    end)
  end
end
