defmodule ExdockWeb.SettingsControls do
  @moduledoc """
  Shared, accessible controls for boolean application settings.
  """

  use ExdockWeb, :html

  attr :id, :string, required: true
  attr :text, :string, required: true
  attr :enabled, :boolean, required: true
  attr :on_click, :string, required: true
  attr :setting_key, :string, required: true
  attr :target, :any, default: nil

  def toggle(assigns) do
    ~H"""
    <div id={@id <> "-row"} class="settings-toggle-row">
      <span id={@id <> "-label"} class="min-w-0 pr-3 text-sm text-mid-visibility">
        {@text}
      </span>

      <button
        id={@id}
        type="button"
        class={[
          "settings-state-control",
          @enabled && "settings-state-control--enabled",
          !@enabled && "settings-state-control--disabled"
        ]}
        phx-click={@on_click}
        phx-value-key={@setting_key}
        phx-value-val={to_string(!@enabled)}
        phx-target={@target}
        aria-pressed={to_string(@enabled)}
        aria-labelledby={@id <> "-label"}
      >
        <span class="settings-state-dot" aria-hidden="true"></span>
        {if @enabled, do: "Enabled", else: "Disabled"}
      </button>
    </div>
    """
  end
end
