defmodule Exdock.Container.AutomationPolicy do
  @moduledoc """
  Canonical eligibility rules for automated container updates.

  The policy is shared by runtime job selection and presentation so the UI's
  enabled state cannot drift from the containers the server will update.
  """

  alias Exdock.Container.SettingsCatalog

  @type image_status :: :unknown | :updated | :outdated | :empty_local_digest | :empty_remote_digest

  @spec participates?(integer(), SettingsCatalog.auto_update(), integer()) :: boolean()
  def participates?(_priority, :disabled, _threshold), do: false
  def participates?(_priority, :enabled, _threshold), do: true
  def participates?(priority, :passthrough, threshold), do: priority > threshold

  @spec eligible?(
          integer(),
          SettingsCatalog.auto_update(),
          integer(),
          boolean(),
          image_status()
        ) :: boolean()
  def eligible?(priority, policy, threshold, running?, image_status) do
    running? and image_status == :outdated and participates?(priority, policy, threshold)
  end
end
