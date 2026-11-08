defmodule Exdock.Protocol.ImageReference do
  @moduledoc """
  Canonical parsing and formatting for Docker-compatible image references.

  Registry ports are inspected separately from the final path segment so they
  are never mistaken for image tags.
  """

  @registries %{
    "docker.io" => {:dockerhub, "https://hub.docker.com/r/"},
    "quay.io" => {:quay, "https://quay.io/repository/"},
    "ghcr.io" => {:ghcr, "https://ghcr.io/"},
    "gcr.io" => {:gcr, "https://gcr.io/"}
  }

  @provider_labels %{
    dockerhub: "Docker Hub",
    quay: "Quay",
    ghcr: "GitHub",
    gcr: "Google"
  }

  @spec image_id?(String.t()) :: boolean()
  def image_id?(reference) when is_binary(reference),
    do: Regex.match?(~r/^(?:sha256:)?[a-fA-F0-9]{64}$/, reference)

  @spec infer_urls_from_tag(String.t()) :: {String.t(), String.t()}
  def infer_urls_from_tag(reference), do: {registry_url(reference), repository_url(reference)}

  @spec registry_url(String.t()) :: String.t()
  def registry_url(reference) when is_binary(reference) do
    if image_id?(reference) do
      ""
    else
      parsed = parse(reference)
      "#{parsed.registry_url}#{parsed.repository}"
    end
  end

  @spec repository_url(String.t()) :: String.t()
  def repository_url(reference) when is_binary(reference) do
    if image_id?(reference), do: "", else: "https://github.com/#{parse(reference).repository}"
  end

  @spec categorize_registry(String.t()) :: String.t()
  def categorize_registry(reference) when is_binary(reference) do
    if image_id?(reference) do
      "Local image"
    else
      parsed = parse(reference)
      Map.get(@provider_labels, parsed.provider, parsed.registry_host)
    end
  end

  @spec repository(String.t()) :: String.t()
  def repository(reference) when is_binary(reference) do
    if image_id?(reference) do
      reference
    else
      reference
      |> String.split("@", parts: 2)
      |> List.first("")
      |> String.split("/", trim: true)
      |> strip_tag_from_last_segment()
      |> Enum.join("/")
    end
  end

  @spec truncate_tag(String.t()) :: String.t()
  def truncate_tag(reference) when is_binary(reference) do
    reference
    |> repository()
    |> String.trim_leading("docker.io/")
    |> String.trim_leading("library/")
  end

  @spec normalize_tag(String.t()) :: String.t()
  def normalize_tag(reference), do: ensure_tag(reference)

  @spec ensure_tag(String.t()) :: String.t()
  def ensure_tag(reference) when is_binary(reference) do
    if image_id?(reference) or digested?(reference) or tagged?(reference), do: reference, else: "#{reference}:latest"
  end

  defp parse(reference) do
    reference
    |> repository()
    |> String.split("/", trim: true)
    |> parse_segments()
  end

  defp parse_segments([name]) do
    %{provider: :dockerhub, registry_host: "docker.io", registry_url: "https://hub.docker.com/_/", repository: name}
  end

  defp parse_segments([registry_host | repository]) when repository != [] do
    if registry_host?(registry_host) do
      {provider, registry_url} = Map.get(@registries, registry_host, {:other, "https://#{registry_host}/"})

      %{
        provider: provider,
        registry_host: registry_host,
        registry_url: registry_url,
        repository: Enum.join(repository, "/")
      }
    else
      %{
        provider: :dockerhub,
        registry_host: "docker.io",
        registry_url: "https://hub.docker.com/r/",
        repository: Enum.join([registry_host | repository], "/")
      }
    end
  end

  defp parse_segments([]) do
    %{provider: :dockerhub, registry_host: "docker.io", registry_url: "https://hub.docker.com/_/", repository: ""}
  end

  defp registry_host?(segment) do
    Map.has_key?(@registries, segment) or segment == "localhost" or String.contains?(segment, [".", ":"])
  end

  defp digested?(reference), do: String.contains?(reference, "@")

  defp tagged?(reference) do
    reference
    |> String.split("/")
    |> List.last("")
    |> String.contains?(":")
  end

  defp strip_tag_from_last_segment([]), do: []

  defp strip_tag_from_last_segment(segments) do
    {leading, [last]} = Enum.split(segments, -1)
    leading ++ [last |> String.split(":", parts: 2) |> List.first("")]
  end
end
