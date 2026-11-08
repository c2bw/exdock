defmodule Exdock.Container.Policy do
  @min_priority 1
  @max_priority 5
  @min_update_threshold 0
  @max_update_threshold 4

  @spec min_priority() :: 1
  def min_priority, do: @min_priority

  @spec max_priority() :: 5
  def max_priority, do: @max_priority

  @spec min_update_threshold() :: 0
  def min_update_threshold, do: @min_update_threshold

  @spec max_update_threshold() :: 4
  def max_update_threshold, do: @max_update_threshold

  @doc """
  Returns whether a container may be recreated through Exdock.

  Exdock's own containers are protected from recreation to avoid disrupting the
  control plane that issued the operation.
  """
  @spec recreatable?(String.t(), map()) :: boolean()
  def recreatable?(container_name, core \\ %{}) do
    not String.contains?(String.downcase(container_name), "exdock") and not protected_label?(core)
  end

  defp protected_label?(%{configuration: %{labels: %{"exdock.protected" => "true"}}}), do: true
  defp protected_label?(_core), do: false

  @doc """
  Returns whether a value is a supported container priority.

  The same priority range is used by container settings, automation thresholds,
  command validation, and delivery-layer parameter parsing.
  """
  @spec valid_priority?(term()) :: boolean()
  def valid_priority?(priority),
    do: is_integer(priority) and priority >= @min_priority and priority <= @max_priority

  @doc """
  Returns whether a value is a supported automation threshold.

  Automation updates containers whose priority is strictly greater than the
  threshold, so `0` selects every priority and `4` selects only priority `5`.
  """
  @spec valid_update_threshold?(term()) :: boolean()
  def valid_update_threshold?(threshold),
    do:
      is_integer(threshold) and threshold >= @min_update_threshold and
        threshold <= @max_update_threshold
end
