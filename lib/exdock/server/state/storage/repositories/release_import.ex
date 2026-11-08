defmodule Exdock.Server.State.Storage.Repositories.ReleaseImport do
  @moduledoc """
  Applies a batch of provider release-fetch results as one database transaction.

  Successful results persist releases and mark the repository as available.
  Provider errors are reduced to the page states understood by the UI.
  """

  alias Exdock.Server.State.Storage.Repositories
  alias Exdock.Server.State.Storage.Persistence.Transaction
  alias Exdock.Domain.Repository

  @type result ::
          {:ok, String.t(), [Repository.Release.t()]}
          | {:error, String.t(), atom()}
          | term()

  @known_errors [:not_found, :rate_limit, :unsupported]

  @spec apply(Repositories.t(), [result()]) :: {:ok, Repositories.t()} | {:error, term()}
  def apply(%Repositories{} = repositories, results) when is_list(results) do
    Transaction.run(fn -> Transaction.reduce(results, repositories, &apply_result/2) end)
  end

  defp apply_result({:ok, url, releases}, %Repositories{} = repositories)
       when is_binary(url) and is_list(releases) do
    with {:ok, repositories} <- Repositories.add(repositories, releases) do
      Repositories.update_metadata(repositories, url, :ok)
    end
  end

  defp apply_result({:error, url, error}, %Repositories{} = repositories) when is_binary(url) do
    Repositories.update_metadata(repositories, url, fetch_error_page_state(error))
  end

  defp apply_result(_unexpected_result, %Repositories{} = repositories), do: {:ok, repositories}

  defp fetch_error_page_state(error) when error in @known_errors, do: error
  defp fetch_error_page_state(_error), do: :error
end
