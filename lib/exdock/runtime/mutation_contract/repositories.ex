defmodule Exdock.Runtime.MutationContract.Repositories do
  @moduledoc false

  alias Exdock.Domain.Repository.Release
  alias Exdock.Runtime.Mutation.Payload

  @spec normalize(term(), term()) :: {:ok, term()} | {:error, term()}
  def normalize(:repository_releases, results) when is_list(results),
    do: normalize(:repository_releases, %Payload.RepositoryReleases{results: results})

  def normalize(
        :repository_releases,
        %Payload.RepositoryReleases{results: results} = payload
      )
      when is_list(results) do
    if Enum.all?(results, &repository_result?/1),
      do: {:ok, payload},
      else: invalid(:repository_releases)
  end

  def normalize(action, _payload), do: invalid(action)

  defp repository_result?({:ok, url, releases}) when is_binary(url) and is_list(releases),
    do: Enum.all?(releases, &match?(%Release{}, &1))

  defp repository_result?({:error, url, _reason}), do: is_binary(url)
  defp repository_result?(_result), do: false

  defp invalid(action), do: {:error, {:invalid_mutation_payload, :repositories, action}}
end
