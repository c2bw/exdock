defmodule ExdockWeb.PageLive.Utils.CommonBroadcastHandler do
  @moduledoc """
  Shared PubSub message reducer for LiveViews.

  Page modules subscribe to the Exdock UI topic and pass generic broadcasts here
  so common assigns such as nodes, containers, logs, status, and rendering
  statistics are updated consistently across pages.
  """

  import Phoenix.Component
  alias Exdock.ReadModel.Projections
  alias Exdock.Runtime.Projection
  alias Exdock.Configuration

  @doc """
  Apply a server broadcast tuple to a LiveView socket.

  Unknown messages are ignored so individual pages can receive a superset of
  broadcasts and still handle only the data they render.
  """
  @spec handle(any(), Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def handle({:update_flash, {flash_type, message}}, socket),
    do: Phoenix.LiveView.put_flash(socket, flash_type, message)

  def handle({source, payload}, socket) when is_atom(source) do
    case Projections.broadcast_assigns(source, payload) do
      {:ok, %{server_configuration: configuration} = assigns} ->
        assign(
          socket,
          Map.put(
            assigns,
            :settings_import_form,
            Phoenix.Component.to_form(%{"server_configuration" => Configuration.to_json(configuration)})
          )
        )

      {:ok, assigns} ->
        assign(socket, assigns)

      :ignored ->
        socket

      :unknown ->
        socket
    end
  end

  def handle(_message, socket), do: socket

  defdelegate node_map!(data), to: Projection
end
