defmodule ExdockWeb.EfficientComponents do
  use Phoenix.Component

  @moduledoc """
   Custom efficient components for ExdockWeb.
  """

  @doc """
    A custom component for a focus wrap.
    Change @rest attribute to named ones to prevent constant sending of classes for each update.
  """
  attr :id, :string, required: true, doc: "The DOM identifier of the container tag."
  attr :class, :string, default: ""
  attr :phx_window_keydown, :any
  attr :phx_key, :any
  attr :phx_click_away, :any
  slot :inner_block, required: true, doc: "The content rendered inside of the container tag."

  def modal_focus_wrap(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="Phoenix.FocusWrap"
      class={@class}
      phx-window-keydown={@phx_window_keydown}
      phx-key={@phx_key}
      phx-click-away={@phx_click_away}
    >
      <span id={"#{@id}-start"} tabindex="0" aria-hidden="true"></span> {render_slot(@inner_block)}
      <span id={"#{@id}-end"} tabindex="0" aria-hidden="true"></span>
    </div>
    """
  end
end
