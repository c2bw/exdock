defmodule Exdock.Size do
  @units ["B", "KB", "MB", "GB", "TB", "PB"]
  @units_binary ["B", "KiB", "MiB", "GiB", "TiB", "PiB"]
  @max_unit_index length(@units) - 1
  @default_format_opts [
    as_string: true,
    binary_units: false,
    decimals: 1,
    increase_decimals: 1,
    no_space: false,
    no_unit: false,
    time_unit: nil,
    truncate_zero_decimals: false
  ]

  @spec unit_name(integer, boolean()) :: String.t()
  defp unit_name(unit_index, use_binary_units) when unit_index <= @max_unit_index do
    unit_names = if use_binary_units, do: @units_binary, else: @units
    Enum.at(unit_names, unit_index)
  end

  @doc """
  Converts a byte size to a human-readable value.

  Options:

    * `:decimals` - number of decimal places to round to. Defaults to 1.
    * `:increase_decimals` - extra decimals for GB and larger values.
    * `:truncate_zero_decimals` - render `1.0` as `1` when possible.
    * `:binary_units` - use KiB/MiB labels and binary values.
    * `:no_space` - omit the space between value and unit.
    * `:time_unit` - append a suffix such as `"/s"`.
    * `:no_unit` - return the value without the unit label.
  """
  @spec human_readable(integer | nil, Keyword.t()) :: String.t()
  def human_readable(bytes, format_opts \\ [])

  def human_readable(bytes, format_opts) when is_integer(bytes) and bytes >= 0 do
    format_opts = normalize_format_opts(format_opts)

    bytes
    |> Kernel.*(1.0)
    |> scale_to_display_unit()
    |> maybe_render_size(format_opts)
  end

  def human_readable(bytes, _format_opts) when is_integer(bytes), do: "-"
  def human_readable(nil, _format_opts), do: "-"

  defp scale_to_display_unit(bytes, unit_index \\ 0)

  defp scale_to_display_unit(bytes, unit_index) when unit_index == @max_unit_index or bytes < 1024 do
    {bytes, unit_index}
  end

  defp scale_to_display_unit(bytes, unit_index) do
    scale_to_display_unit(bytes / 1024, unit_index + 1)
  end

  defp maybe_render_size({bytes, unit_index}, format_opts) do
    case format_opts[:as_string] do
      true -> format_size_string(bytes, unit_index, format_opts)
      false -> {bytes, unit_index}
    end
  end

  defp format_size_string(bytes, unit_index, format_opts) do
    decimals = decimals_for_output(format_opts, unit_index)
    use_binary_units = format_opts[:binary_units]

    value =
      convert_units(bytes, unit_index, use_binary_units)
      |> Float.round(decimals)
      |> maybe_truncate_zero_decimals(format_opts)

    value
    |> append_unit_suffix(unit_index, use_binary_units, format_opts)
    |> maybe_append_time_unit(format_opts)
  end

  defp normalize_format_opts(format_opts) do
    Keyword.merge(@default_format_opts, format_opts)
  end

  defp convert_units(bytes, _unit_index, _use_binary_units = true), do: bytes

  defp convert_units(bytes, unit_index, _use_binary_units = false) do
    bytes * (Integer.pow(1024, unit_index) / Integer.pow(10, 3 * unit_index))
  end

  defp decimals_for_output(format_opts, unit_index) do
    base_decimals = format_opts[:decimals]
    additional_decimals = format_opts[:increase_decimals]

    case {additional_decimals, unit_index > 2} do
      {0, _} -> base_decimals
      {value, true} when value > 0 -> base_decimals + value
      {_value, _} -> base_decimals
    end
  end

  defp maybe_truncate_zero_decimals(value, format_opts) do
    if format_opts[:truncate_zero_decimals] and value - trunc(value) == 0 do
      trunc(value)
    else
      value
    end
  end

  defp append_unit_suffix(value, unit_index, use_binary_units, format_opts) do
    unit =
      if format_opts[:no_unit],
        do: "",
        else: unit_name(unit_index, use_binary_units)

    if format_opts[:no_space] do
      "#{value}#{unit}"
    else
      "#{value} #{unit}"
    end
  end

  defp maybe_append_time_unit(text, format_opts) do
    time_unit = format_opts[:time_unit]

    if is_nil(time_unit) do
      text
    else
      "#{text}#{time_unit}"
    end
  end

  @doc """
  Converts two byte sizes to values rendered with the master's unit.

  The third return value is the shared unit label. Use this when a UI needs
  aligned values such as `{"1.5", "0.5", "KB"}`.
  """
  @spec normalized_bytes(integer | nil, integer | nil, Keyword.t()) :: {String.t(), String.t(), String.t()}
  def normalized_bytes(master, slave, opts \\ [])

  def normalized_bytes(master, slave, _opts) when is_nil(master) or is_nil(slave) do
    {"-", "-", ""}
  end

  def normalized_bytes(master, slave, opts) when is_integer(master) and is_integer(slave) do
    opts = normalize_format_opts(opts)
    {master_value, unit_index} = scale_to_display_unit(master * 1.0)
    slave_value = bytes_in_unit(slave, unit_index)
    value_opts = normalized_value_opts(opts)

    {
      format_size_string(master_value, unit_index, value_opts),
      format_size_string(slave_value, unit_index, value_opts),
      unit_with_time_suffix(unit_index, opts)
    }
  end

  defp normalized_value_opts(opts) do
    opts
    |> Keyword.put(:no_unit, true)
    |> Keyword.put(:time_unit, nil)
    |> Keyword.put(:no_space, true)
  end

  defp bytes_in_unit(bytes, 0), do: bytes
  defp bytes_in_unit(bytes, unit_index), do: bytes / Integer.pow(1024, unit_index)

  defp unit_with_time_suffix(unit_index, opts) do
    "#{unit_name(unit_index, opts[:binary_units])}#{time_unit_suffix(opts)}"
  end

  defp time_unit_suffix(opts) do
    opts[:time_unit] || ""
  end
end
