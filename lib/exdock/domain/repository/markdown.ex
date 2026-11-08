defmodule Exdock.Domain.Repository.Markdown do
  @moduledoc false

  @allowed_tags ~w[
    a blockquote br code del div em h1 h2 h3 h4 h5 h6 hr img li ol p pre
    strong sup table tbody td th thead tr ul
  ]
  @global_attributes ~w[class id]
  @tag_attributes %{
    "a" => ~w[href title],
    "code" => ~w[class],
    "img" => ~w[alt src title],
    "li" => ~w[value],
    "ol" => ~w[start],
    "td" => ~w[align],
    "th" => ~w[align]
  }
  @link_schemes ["http", "https", "mailto"]
  @image_schemes ["http", "https"]
  @sanitize_options [
    tags: @allowed_tags,
    clean_content_tags: ~w[script style],
    tag_attributes: @tag_attributes,
    generic_attributes: @global_attributes,
    url_schemes: @link_schemes,
    link_rel: "noopener noreferrer",
    strip_comments: true
  ]

  @spec render(String.t()) :: String.t()
  def render(markdown) when is_binary(markdown) do
    document =
      MDEx.new(
        markdown: markdown,
        extension: [alerts: true, strikethrough: true, table: true],
        render: [unsafe: false],
        sanitize: @sanitize_options
      )
      |> MDEx.Document.run()
      |> sanitize_urls()

    MDEx.to_html!(document)
  end

  defp sanitize_urls(document) do
    document
    |> MDEx.Document.update_nodes(MDEx.Link, &sanitize_url(&1, @link_schemes))
    |> MDEx.Document.update_nodes(MDEx.Image, &sanitize_url(&1, @image_schemes))
  end

  defp sanitize_url(%{url: url} = node, allowed_schemes) when is_binary(url) do
    if safe_url?(url, allowed_schemes), do: node, else: %{node | url: ""}
  end

  defp safe_url?(url, allowed_schemes) do
    url = String.trim(url)

    not obfuscated_scheme?(url) and
      case URI.parse(url) do
        %URI{scheme: nil} -> url != ""
        %URI{scheme: scheme} -> String.downcase(scheme) in allowed_schemes
      end
  end

  defp obfuscated_scheme?(url) do
    prefix = url |> String.split(["/", "?", "#"], parts: 2) |> List.first("")
    String.contains?(prefix, "&") or Regex.match?(~r/[\x00-\x20\x7f]/u, prefix)
  end
end
