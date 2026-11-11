defmodule Exdock.Protocol.Compatibility do
  @moduledoc """
  Release and wire compatibility values shared by server and agent.

  Wire compatibility, agent release compatibility, and runtime-bundle
  compatibility are independent contracts and are versioned separately.
  """

  @wire_version 6
  @agent_version "1.3.0"
  @agent_requirement "~> 1.3.0"
  @runtime_bundle_version "1"

  @spec wire_version() :: pos_integer()
  def wire_version, do: @wire_version

  @spec agent_version() :: String.t()
  def agent_version, do: @agent_version

  @spec agent_requirement() :: String.t()
  def agent_requirement, do: @agent_requirement

  @spec runtime_bundle_version() :: String.t()
  def runtime_bundle_version, do: @runtime_bundle_version
end
