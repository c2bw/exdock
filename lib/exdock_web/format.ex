defmodule ExdockWeb.Format do
  @moduledoc """
  Presentation-oriented value formatting shared by web components.
  """

  @spec percentage(float() | nil, non_neg_integer()) :: String.t()
  def percentage(value, decimals \\ 1)

  def percentage(nil, _decimals), do: "-"

  def percentage(value, decimals) do
    "#{Float.round(value, decimals)}%"
  end
end
