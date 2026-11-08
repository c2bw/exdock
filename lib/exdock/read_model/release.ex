defmodule Exdock.ReadModel.Release do
  @moduledoc """
  Render-ready release projection.

  Compressed runtime payloads and provider implementation details are resolved
  once at the read boundary instead of in LiveView templates.
  """

  defstruct [
    :source,
    :repository,
    :name,
    :version,
    :release_url,
    :html_description,
    :time_released,
    :provider_icon,
    :repository_label
  ]

  @type t :: %__MODULE__{
          source: atom(),
          repository: String.t(),
          name: String.t(),
          version: String.t(),
          release_url: String.t(),
          html_description: String.t(),
          time_released: DateTime.t(),
          provider_icon: String.t() | nil,
          repository_label: String.t()
        }

  @spec from_domain(map()) :: t()
  def from_domain(release) when is_map(release) do
    %__MODULE__{
      source: release.source,
      repository: release.repository,
      name: release.name,
      version: release.version,
      release_url: release.release_url,
      html_description: inflate(release.compressed_html_description),
      time_released: release.time_released,
      provider_icon: provider_icon(release.source),
      repository_label: repository_label(release.repository)
    }
  end

  defp inflate(compressed) when is_binary(compressed), do: :zlib.gunzip(compressed)

  defp provider_icon(:github), do: "github-mark.svg"
  defp provider_icon(:gitlab), do: "gitlab-logo.svg"
  defp provider_icon(_source), do: nil

  defp repository_label(url) do
    url
    |> URI.parse()
    |> then(fn uri -> Enum.join(Enum.reject([uri.host, uri.path], &is_nil/1), "") end)
    |> String.trim_leading("/")
    |> String.downcase()
  end
end
