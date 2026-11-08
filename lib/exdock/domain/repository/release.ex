defmodule Exdock.Domain.Repository.Release do
  alias Exdock.Domain.Repository.Markdown

  @empty_description ""

  defstruct [
    :source,
    :repository,
    :name,
    :version,
    :release_url,
    :compressed_description,
    :compressed_html_description,
    :time_released
  ]

  @type t :: %__MODULE__{
          source: atom(),
          repository: String.t(),
          name: String.t(),
          version: String.t(),
          release_url: String.t(),
          compressed_description: binary(),
          compressed_html_description: binary(),
          time_released: DateTime.t()
        }

  @spec new(atom(), String.t(), String.t(), String.t(), String.t(), String.t() | nil, String.t() | nil, DateTime.t()) :: t()
  def new(source, repository, name, version, release_url, description, time_released, %DateTime{} = fallback_time)
      when is_binary(time_released) or is_nil(time_released) do
    time_released
    |> parse_release_time(fallback_time)
    |> then(&new(source, repository, name, version, release_url, description, &1))
  end

  @spec new(atom(), String.t(), String.t(), String.t(), String.t(), String.t() | nil, DateTime.t()) :: t()
  def new(source, repository, name, version, release_url, description, %DateTime{} = time_released) do
    {compressed_description, compressed_html_description} =
      build_description_payloads(description)

    %__MODULE__{
      source: source,
      repository: repository,
      name: name,
      version: version,
      release_url: release_url,
      compressed_description: compressed_description,
      compressed_html_description: compressed_html_description,
      time_released: time_released
    }
  end

  @doc false
  @spec from_persisted(map()) :: t()
  def from_persisted(release) when is_map(release) do
    new(
      release.source,
      release.url,
      release.name,
      release.version,
      release.release_url,
      inflate_markdown(release.description),
      release.time_released
    )
  end

  defp parse_release_time(value, %DateTime{} = fallback_time) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, time, _offset} -> time
      {:error, _reason} -> fallback_time
    end
  end

  defp parse_release_time(nil, %DateTime{} = fallback_time), do: fallback_time

  # Keep both markdown and rendered HTML compressed in runtime state so list views
  # can render fast without carrying large release-note strings in memory.
  defp build_description_payloads(description) do
    description = normalize_description(description)

    {
      compress(description),
      description |> render_markdown() |> compress()
    }
  end

  defp normalize_description(nil), do: @empty_description
  defp normalize_description(description) when is_binary(description), do: description

  # Database rows store only the compressed markdown; rebuild the HTML payload.
  defp inflate_markdown(compressed_description) when is_binary(compressed_description),
    do: :zlib.gunzip(compressed_description)

  defp compress(text) when is_binary(text), do: :zlib.gzip(text)

  @spec render_markdown(String.t()) :: String.t()
  defp render_markdown(markdown) when is_binary(markdown), do: Markdown.render(markdown)

  @doc """
   Compare two releases and return true if the repository and version are the same.
  """
  def same_version(%__MODULE__{} = left, %__MODULE__{} = right),
    do: {left.repository, left.version} == {right.repository, right.version}
end
