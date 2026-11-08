defmodule Exdock.AgentRuntime.Size do
  @moduledoc """
  Small runtime-owned byte formatter used by image-pull progress messages.

  Keeping this helper in the AgentRuntime namespace ensures every downloadable
  BEAM belongs to the validated runtime bundle.
  """

  @units ["B", "KB", "MB", "GB", "TB", "PB"]
  @binary_units ["B", "KiB", "MiB", "GiB", "TiB", "PiB"]

  @spec human_readable(non_neg_integer(), keyword()) :: String.t()
  def human_readable(bytes, opts \\ []) when is_integer(bytes) and bytes >= 0 do
    {value, unit_index} = scale(bytes * 1.0)
    binary? = Keyword.get(opts, :binary_units, false)
    decimals = Keyword.get(opts, :decimals, 1)
    units = if binary?, do: @binary_units, else: @units

    value =
      if binary? do
        value
      else
        value * (Integer.pow(1024, unit_index) / Integer.pow(1000, unit_index))
      end

    "#{Float.round(value, decimals)} #{Enum.at(units, unit_index)}"
  end

  defp scale(value, unit_index \\ 0)

  defp scale(value, unit_index) when value < 1024 or unit_index == 5,
    do: {value, unit_index}

  defp scale(value, unit_index), do: scale(value / 1024, unit_index + 1)
end
