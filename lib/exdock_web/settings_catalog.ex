defmodule ExdockWeb.SettingsCatalog do
  @moduledoc """
  Presentation metadata for user-setting controls.

  Field identity remains owned by `Exdock.Settings.UserFieldCatalog`; this
  module adds the labels, events, and bounds needed by the web interface.
  """

  alias Exdock.Container.Policy
  alias Exdock.Settings.UserFieldCatalog

  @preference_toggles [
    {:pageload_node_refresh, "Auto-refresh nodes on page load", "change_user_settings"},
    {:container_resources, "Container resource statistics", "change_user_settings"},
    {:rendering_statistics, "Rendering statistics", "toggle_rendering_statistics"},
    {:automation_enabled, "Automation", "change_user_settings"}
  ]

  @automation_toggles [
    {:automation_enabled, "Automation", "change_user_settings"},
    {:auto_update_releases, "Update releases", "change_user_settings"},
    {:auto_update_containers, "Update containers", "change_user_settings"}
  ]

  @type toggle :: %{
          key: UserFieldCatalog.key(),
          external: String.t(),
          label: String.t(),
          event: String.t()
        }

  @type threshold :: %{
          key: :auto_update_above,
          external: String.t(),
          label: String.t(),
          event: String.t(),
          min: non_neg_integer(),
          max: non_neg_integer()
        }

  @spec toggles(:preferences | :automation) :: [toggle()]
  def toggles(:preferences), do: Enum.map(@preference_toggles, &toggle/1)
  def toggles(:automation), do: Enum.map(@automation_toggles, &toggle/1)

  @spec automation_threshold() :: threshold()
  def automation_threshold do
    %{
      key: :auto_update_above,
      external: UserFieldCatalog.external(:auto_update_above),
      label: "Update containers with priority above",
      event: "change_user_settings",
      min: Policy.min_update_threshold(),
      max: Policy.max_update_threshold()
    }
  end

  defp toggle({key, label, event}) do
    %{key: key, external: UserFieldCatalog.external(key), label: label, event: event}
  end
end
