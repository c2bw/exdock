defmodule Exdock.Server.Jobs.Local.Releases.ResponseMapper do
  @moduledoc """
  Maps provider-specific release payloads to repository release structures.
  """

  alias Exdock.Server.Jobs.Local.Releases.Provider
  alias Exdock.Domain.Repository

  @spec parse(Provider.name(), String.t(), String.t(), [map()], DateTime.t()) :: [Repository.Release.t()]
  def parse(provider, repo_name, repo_url, body, %DateTime{} = fetched_at)
      when is_atom(provider) and is_binary(repo_name) and is_binary(repo_url) and is_list(body) do
    fields = Provider.release_field_paths(provider)

    body
    |> Enum.reject(&(provider == :github and fetch_value(&1, :draft) == true))
    |> Enum.map(fn response ->
      Repository.Release.new(
        provider,
        repo_url,
        repo_name,
        extract_field(response, fields.version),
        extract_field(response, fields.release_url),
        extract_field(response, fields.description),
        extract_field(response, fields.released_at),
        fetched_at
      )
    end)
  end

  defp extract_field(response, path) when is_list(path) do
    Enum.reduce_while(path, response, fn key, current ->
      case fetch_value(current, key) do
        nil -> {:halt, nil}
        value -> {:cont, value}
      end
    end)
  end

  defp fetch_value(response, key) when is_map(response) do
    case Map.fetch(response, key) do
      {:ok, value} -> value
      :error -> Map.get(response, Atom.to_string(key))
    end
  end

  defp fetch_value(_response, _key), do: nil
end
