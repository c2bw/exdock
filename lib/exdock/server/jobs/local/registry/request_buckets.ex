defmodule Exdock.Server.Jobs.Local.Registry.RequestBuckets do
  @moduledoc """
  Builds the per-registry execution plan for remote tag requests.

  Requests for the same canonical registry endpoint share one bucket while
  malformed references remain isolated by their original image tag.
  """

  alias Exdock.Server.RegistryFetchLimiter

  defstruct buckets: [],
            max_concurrency: 1

  @type request :: %{tag: String.t(), platform: String.t()}
  @type t :: %__MODULE__{
          buckets: [[request()]],
          max_concurrency: pos_integer()
        }

  @spec plan([request()]) :: t()
  def plan(requests) when is_list(requests) do
    buckets = group(requests)
    %__MODULE__{buckets: buckets, max_concurrency: max(length(buckets), 1)}
  end

  @spec group([request()]) :: [[request()]]
  def group(requests) when is_list(requests) do
    {endpoint_order, buckets} =
      Enum.reduce(requests, {[], %{}}, fn %{tag: image_tag} = request, {endpoint_order, buckets} ->
        endpoint = bucket_key(image_tag)

        if Map.has_key?(buckets, endpoint) do
          {endpoint_order, Map.update!(buckets, endpoint, &[request | &1])}
        else
          {[endpoint | endpoint_order], Map.put(buckets, endpoint, [request])}
        end
      end)

    endpoint_order
    |> Enum.reverse()
    |> Enum.map(fn endpoint ->
      buckets
      |> Map.fetch!(endpoint)
      |> Enum.reverse()
    end)
  end

  @spec bucket_key(String.t()) :: {:registry, term()} | {:invalid_reference, String.t()}
  def bucket_key(image_tag) when is_binary(image_tag) do
    case RegistryFetchLimiter.endpoint(image_tag) do
      {:ok, endpoint} -> {:registry, endpoint}
      {:error, _error} -> {:invalid_reference, image_tag}
    end
  end
end
