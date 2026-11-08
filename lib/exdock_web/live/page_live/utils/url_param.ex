defmodule ExdockWeb.PageLive.Utils.URLParam do
  @moduledoc false

  @spec encode(String.t()) :: String.t()
  def encode(value) when is_binary(value), do: Base.url_encode64(value, padding: false)

  @spec decode(String.t()) :: {:ok | :invalid, String.t()}
  def decode(value) when is_binary(value) do
    case Base.url_decode64(value, padding: false) do
      {:ok, decoded} ->
        if String.valid?(decoded), do: {:ok, decoded}, else: {:invalid, ""}

      :error ->
        {:invalid, ""}
    end
  end
end
