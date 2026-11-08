defmodule Exdock.Database.StoredAtom do
  @moduledoc """
  Converts bounded atom fields at the database boundary.

  Several persisted records keep enum-like values as strings because Ecto schema
  fields are strings, while the server runtime uses atoms for pattern matching.
  Callers must pass the allowed atoms explicitly so stale or hand-edited rows do
  not create new atoms while loading.
  """

  @spec dump(atom()) :: String.t()
  def dump(value) when is_atom(value), do: Atom.to_string(value)

  @spec load(String.t() | atom() | nil, [atom()], atom()) :: atom()
  def load(value, allowed, fallback) when is_binary(value) and is_list(allowed) and is_atom(fallback) do
    Enum.find(allowed, fallback, &(Atom.to_string(&1) == value))
  end

  def load(value, allowed, fallback) when is_atom(value) and is_list(allowed) and is_atom(fallback) do
    if value in allowed, do: value, else: fallback
  end

  def load(_value, _allowed, fallback) when is_atom(fallback), do: fallback
end
