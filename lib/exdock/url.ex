defmodule Exdock.URL do
  @doc """
  Normalizes a URL used to link to an external service.

  URLs without an HTTP scheme are prefixed with `https://`. An empty string is
  returned unchanged.
  """
  @spec normalize_external(String.t()) :: String.t()
  def normalize_external(url) do
    cond do
      url == "" -> url
      external?(url) -> url
      true -> "https://#{url}"
    end
  end

  defp external?(url) when is_binary(url) do
    String.starts_with?(url, ["http://", "https://"])
  end
end
