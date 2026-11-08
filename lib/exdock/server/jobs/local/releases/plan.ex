defmodule Exdock.Server.Jobs.Local.Releases.Plan do
  @moduledoc """
  Pure repository selection for release-fetch jobs.

  Repository URLs are de-duplicated before being partitioned by provider
  support. The caller can then report unsupported repositories and construct
  provider requests without repeating selection logic.
  """

  alias Exdock.Server.Jobs.Local.Releases.HTTPRequest
  alias Exdock.Domain.Repository

  @type t :: %{
          supported_urls: [String.t()],
          unsupported_urls: [String.t()]
        }

  @spec build([Repository.t()]) :: t()
  def build(repositories) when is_list(repositories) do
    {supported, unsupported} =
      repositories
      |> Enum.uniq_by(& &1.url)
      |> Enum.split_with(&supported_repository?/1)

    %{
      supported_urls: urls(supported),
      unsupported_urls: urls(unsupported)
    }
  end

  @spec unsupported_results(t()) :: [{:error, String.t(), :unsupported}]
  def unsupported_results(%{unsupported_urls: urls}) do
    Enum.map(urls, &{:error, &1, :unsupported})
  end

  defp supported_repository?(%Repository{url: url}),
    do: HTTPRequest.supported_provider?(url)

  defp urls(repositories), do: Enum.map(repositories, & &1.url)
end
