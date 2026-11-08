defmodule ExdockWeb.PageLive.Utils.ContainerSettingsEvents do
  @moduledoc """
  Validates container-settings UI events and submits their operations.

  LiveComponents remain responsible for presenting validation and operation
  failures in the context of their own UI.
  """

  alias Exdock.Operations
  alias ExdockWeb.PageLive.Utils.EventParams
  alias ExdockWeb.PageLive.Utils.LiveOperation

  @type validation_error :: :invalid_priority | :invalid_auto_update | :invalid_request
  @type result :: {:operation, Operations.result()} | {:invalid, validation_error()} | :noop

  @spec change_priority(map()) :: result()
  def change_priority(%{"node" => node, "container" => container, "priority" => priority}) do
    with true <- present?(node),
         true <- present?(container),
         {:ok, priority} <- EventParams.priority(priority) do
      {:operation, Operations.set_container_priority(node, container, priority)}
    else
      _invalid -> {:invalid, :invalid_priority}
    end
  end

  def change_priority(_params), do: {:invalid, :invalid_request}

  @spec change_auto_update(map()) :: result()
  def change_auto_update(%{
        "node" => node,
        "container" => container,
        "current-policy" => current_policy,
        "next" => direction
      }) do
    submit_auto_update(node, container, current_policy, direction)
  end

  def change_auto_update(_params), do: {:invalid, :invalid_request}

  @spec apply_priority_result(Phoenix.LiveView.Socket.t(), result()) ::
          Phoenix.LiveView.Socket.t()
  def apply_priority_result(socket, {:operation, operation}),
    do: LiveOperation.handle_component(socket, operation)

  def apply_priority_result(socket, {:invalid, :invalid_priority}),
    do: LiveOperation.invalid_component(socket, "Priority must be between 1 and 5")

  def apply_priority_result(socket, {:invalid, :invalid_request}),
    do: LiveOperation.invalid_component(socket, "Invalid priority request")

  @spec apply_auto_update_result(Phoenix.LiveView.Socket.t(), result()) ::
          Phoenix.LiveView.Socket.t()
  def apply_auto_update_result(socket, {:operation, operation}),
    do: LiveOperation.handle_component(socket, operation)

  def apply_auto_update_result(socket, :noop), do: socket

  def apply_auto_update_result(socket, {:invalid, _reason}),
    do: LiveOperation.invalid_component(socket, "Invalid auto-update request")

  @doc false
  @spec next_auto_update_policy(any(), any()) ::
          {:ok, Operations.auto_update_policy()} | :noop | {:error, :invalid_auto_update}
  def next_auto_update_policy(current_policy, direction) do
    case {normalize_auto_update_policy(current_policy), direction} do
      {:passthrough, "next"} -> {:ok, :enabled}
      {:passthrough, "prev"} -> {:ok, :disabled}
      {:enabled, "prev"} -> {:ok, :passthrough}
      {:disabled, "next"} -> {:ok, :passthrough}
      {:enabled, "next"} -> :noop
      {:disabled, "prev"} -> :noop
      _invalid -> {:error, :invalid_auto_update}
    end
  end

  defp submit_auto_update(node, container, current_policy, direction) do
    with true <- present?(node),
         true <- present?(container),
         {:ok, next_policy} <- next_auto_update_policy(current_policy, direction) do
      {:operation, Operations.set_container_auto_update(node, container, next_policy)}
    else
      :noop -> :noop
      _invalid -> {:invalid, :invalid_auto_update}
    end
  end

  defp normalize_auto_update_policy(policy) when policy in [:passthrough, :enabled, :disabled], do: policy
  defp normalize_auto_update_policy("passthrough"), do: :passthrough
  defp normalize_auto_update_policy("enabled"), do: :enabled
  defp normalize_auto_update_policy("disabled"), do: :disabled
  defp normalize_auto_update_policy(_unknown), do: nil

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
