defmodule ExdockWeb.Automation.Settings do
  @moduledoc """
  Stateless automation controls rendered by the owning automation LiveView.
  """

  use ExdockWeb, :html

  alias Exdock.Schedule
  alias Exdock.Datetime
  alias ExdockWeb.{SettingsCatalog, SettingsControls}

  attr :id, :string, required: true
  attr :user_settings, :any, required: true
  attr :clock_now, :any, required: true
  attr :cron_form, :any, required: true

  def render(%{user_settings: settings, clock_now: %DateTime{} = clock_now} = assigns) do
    next_run = calculate_next_run(settings.cron_string, clock_now)

    assigns =
      assigns
      |> assign(:next_run, next_run)
      |> assign(:until_next_run, calculate_duration_until(next_run, clock_now))
      |> assign(:toggle_controls, SettingsCatalog.toggles(:automation))
      |> assign(:threshold_control, SettingsCatalog.automation_threshold())

    ~H"""
    <section id={@id <> "-panel"} class="automation-panel automation-panel--controls mt-4">
      <header class="automation-panel-header">
        <div class="flex min-w-0 items-center gap-3">
          <span class="control-icon-tile automation-panel-icon" aria-hidden="true">
            <.icon name="hero-calendar-days" class="h-5 w-5" />
          </span>
          <div class="min-w-0">
            <h2 class="automation-panel-title">Automation controls</h2>
            <p class="automation-panel-description">
              Configure what runs and when it should start.
            </p>
          </div>
        </div>

        <span class={[
          "automation-status-pill",
          @user_settings.automation_enabled && "automation-status-pill--enabled"
        ]}>
          <span class="automation-status-dot" aria-hidden="true"></span>
          {if @user_settings.automation_enabled, do: "Active", else: "Paused"}
        </span>
      </header>

      <div class="automation-panel-body">
        <div class="automation-settings-stack w-full min-w-fit">
          <SettingsControls.toggle
            :for={control <- @toggle_controls}
            id={"automation-settings-toggle-#{control.external}"}
            text={control.label}
            enabled={Map.fetch!(@user_settings, control.key)}
            on_click={control.event}
            setting_key={control.external}
          />
          <.settings_value_modify
            text={@threshold_control.label}
            on_click={@threshold_control.event}
            key={@threshold_control.external}
            current={Map.fetch!(@user_settings, @threshold_control.key)}
            min={@threshold_control.min}
            max={@threshold_control.max}
          />
          <.cron_input
            current_cron={@user_settings.cron_string}
            form={@cron_form}
            form_id={@id <> "-cron-form"}
          />
          <.automation_info
            next_run={@next_run}
            until_next_run={@until_next_run}
            enabled={@user_settings.automation_enabled}
            update_containers={@user_settings.auto_update_containers}
            update_releases={@user_settings.auto_update_releases}
          />
        </div>
      </div>
    </section>
    """
  end

  defp settings_value_modify(assigns) do
    ~H"""
    <div class="automation-control-row">
      <p class="automation-control-label">{@text}</p>

      <div class="automation-stepper">
        <button
          type="button"
          class="control-lift-action automation-stepper-button"
          aria-label="Decrease priority threshold"
          phx-click={@on_click}
          phx-value-key={@key}
          phx-value-val={Kernel.max(@min, @current - 1)}
        >
          <.icon name="hero-minus" class="h-3.5 w-3.5" />
        </button>

        <span class="automation-stepper-value" aria-label={"Current threshold: #{@current}"}>
          {@current}
        </span>

        <button
          type="button"
          class="control-lift-action automation-stepper-button"
          aria-label="Increase priority threshold"
          phx-click={@on_click}
          phx-value-key={@key}
          phx-value-val={Kernel.min(@max, @current + 1)}
        >
          <.icon name="hero-plus" class="h-3.5 w-3.5" />
        </button>
      </div>
    </div>
    """
  end

  defp cron_input(assigns) do
    ~H"""
    <div class="automation-control-row">
      <div>
        <p class="automation-control-label">Automation cron string</p>
        <p class="mt-0.5 font-mono text-xxs text-low-visibility">
          Current schedule: <span class="text-mid-visibility">{@current_cron}</span>
        </p>
      </div>

      <div class="automation-schedule-form">
        <.form
          for={@form}
          id={@form_id}
          class="automation-schedule-form"
          phx-submit="set_cron"
        >
          <div class="automation-cron-field">
            <.input
              type="text"
              field={@form[:cron_string]}
              id="cron_input_string"
              placeholder={@current_cron}
              bg_color="bg-primary"
              text_color="text-high-visibility"
              custom_classes="text-start font-mono"
              aria-label="Automation cron schedule"
            />
          </div>
          <button type="submit" class="control-lift-action automation-action-button">
            <.icon name="hero-check" class="h-3.5 w-3.5" />
            <span>Set</span>
          </button>
        </.form>

        <button
          type="button"
          class="control-lift-action automation-action-button automation-action-button--primary"
        >
          <span class="inline-flex items-center gap-1.5" phx-click="run_automation">
            <.icon name="hero-play" class="h-3.5 w-3.5" /> run
          </span>
        </button>
      </div>
    </div>
    """
  end

  defp automation_info(assigns) do
    ~H"""
    <div class="automation-info">
      <div class="automation-info-item">
        <span class="control-icon-tile automation-info-icon" aria-hidden="true">
          <.icon name="hero-clock" class="h-4 w-4" />
        </span>
        <div>
          <p class="font-mono text-xxs font-bold uppercase tracking-wider text-low-visibility">Next run</p>
          <p id="automation-next-run" class="mt-1 font-mono text-xs text-mid-visibility">
            {if @next_run, do: Datetime.prettify(@next_run), else: "No future runs"}
          </p>
          <p :if={@next_run} class="mt-0.5 font-mono text-xxs text-low-visibility">
            {@until_next_run} from now
          </p>
        </div>
      </div>

      <div class="automation-info-item">
        <span class="control-icon-tile automation-info-icon" aria-hidden="true">
          <.icon name="hero-arrow-path-rounded-square" class="h-4 w-4" />
        </span>
        <div>
          <p class="font-mono text-xxs font-bold uppercase tracking-wider text-low-visibility">Run scope</p>
          <p class="mt-1 font-mono text-xs leading-5 text-mid-visibility">
            <%= case @enabled do %>
              <% true -> %>
                Registry{if @update_containers, do: ", outdated containers"}{if @update_releases, do: ", releases"}
              <% false -> %>
                Automation is disabled
            <% end %>
          </p>
        </div>
      </div>
    </div>
    """
  end

  @spec calculate_next_run(String.t(), DateTime.t()) :: DateTime.t() | nil
  defp calculate_next_run(cron_string, now), do: Schedule.next_run(cron_string, now)

  @spec calculate_duration_until(DateTime.t() | nil, DateTime.t()) :: String.t()
  defp calculate_duration_until(nil, _now), do: "-"
  defp calculate_duration_until(next_run, now), do: Datetime.duration_until(next_run, now)
end
