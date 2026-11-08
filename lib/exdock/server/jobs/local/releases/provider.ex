defmodule Exdock.Server.Jobs.Local.Releases.Provider do
  @moduledoc """
  Resolves supported repository providers and their API profiles.
  """

  @profiles %{
    github: %{
      host: "github.com",
      release_field_paths: %{
        version: [:tag_name],
        release_url: [:html_url],
        description: [:body],
        released_at: [:published_at]
      }
    },
    gitlab: %{
      host: "gitlab.com",
      release_field_paths: %{
        version: [:tag_name],
        release_url: [:links, :self],
        description: [:description],
        released_at: [:released_at]
      }
    }
  }

  @host_to_provider Map.new(@profiles, fn {provider, %{host: host}} -> {host, provider} end)
  @hosts Map.keys(@host_to_provider)

  @type name :: :github | :gitlab

  @spec hosts() :: [String.t()]
  def hosts, do: @hosts

  @spec supported?(String.t()) :: boolean()
  def supported?(repository_url), do: match?({:ok, _provider, _repo_name}, resolve(repository_url))

  @spec resolve(String.t()) :: {:ok, name(), String.t()} | :unsupported
  def resolve(repository_url) when is_binary(repository_url) do
    case repository_url |> normalize_repository_url() |> String.split("/", parts: 2) do
      [host, repo_name] when host in @hosts and repo_name != "" ->
        {:ok, Map.fetch!(@host_to_provider, host), repo_name}

      _invalid ->
        :unsupported
    end
  end

  @spec releases_url(name(), String.t()) :: String.t()
  def releases_url(:github, repo), do: "https://api.github.com/repos/#{repo}/releases"

  def releases_url(:gitlab, repo),
    do: "https://gitlab.com/api/v4/projects/#{URI.encode_www_form(repo)}/releases"

  @spec release_field_paths(name()) :: map()
  def release_field_paths(provider), do: @profiles |> Map.fetch!(provider) |> Map.fetch!(:release_field_paths)

  @spec bearer_token(name()) :: String.t() | nil
  def bearer_token(:github), do: Application.get_env(:exdock, :github_api_token)
  def bearer_token(:gitlab), do: nil

  defp normalize_repository_url(repository_url) do
    repository_url
    |> String.trim()
    |> strip_protocol()
    |> String.trim_trailing("/")
  end

  defp strip_protocol(repository_url) do
    repository_url
    |> String.trim_leading("https://")
    |> String.trim_leading("http://")
  end
end
