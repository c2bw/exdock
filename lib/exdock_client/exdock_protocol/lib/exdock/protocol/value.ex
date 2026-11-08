defmodule Exdock.Protocol.Value do
  @moduledoc """
  Converts runtime values into protocol-safe terms.

  Generated client structs and calendar values are normalized before they cross
  the wire so receiving applications never need those implementation types.
  """

  @spec encode(term()) :: term()
  def encode(nil), do: nil
  def encode(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  def encode(%NaiveDateTime{} = datetime), do: NaiveDateTime.to_iso8601(datetime)
  def encode(%Time{} = time), do: Time.to_iso8601(time)
  def encode(%Date{} = date), do: Date.to_iso8601(date)

  def encode(struct) when is_struct(struct) do
    struct
    |> Map.from_struct()
    |> encode()
  end

  def encode(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {encode_key(key), encode(value)} end)
  end

  def encode(list) when is_list(list), do: Enum.map(list, &encode/1)

  def encode(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&encode/1)
    |> List.to_tuple()
  end

  def encode(value), do: value

  defp encode_key(key) when is_binary(key), do: key
  defp encode_key(key) when is_atom(key), do: Atom.to_string(key)
  defp encode_key(key), do: to_string(key)
end
