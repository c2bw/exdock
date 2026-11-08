defmodule Exdock.Runtime.MutationContract.Images do
  @moduledoc false

  alias Exdock.Runtime.Mutation.Payload

  @spec normalize(term(), term()) :: {:ok, term()} | {:error, term()}
  def normalize(:delete_lock, {node, id, locked?}),
    do: normalize(:delete_lock, %Payload.ImageDeleteLock{node: node, id: id, locked?: locked?})

  def normalize(
        :delete_lock,
        %Payload.ImageDeleteLock{node: node, id: id, locked?: locked?} = payload
      )
      when is_binary(node) and is_binary(id) and is_boolean(locked?),
      do: {:ok, payload}

  def normalize(:repository_url, {:single, image, url}),
    do: normalize(:repository_url, [{image, url}])

  def normalize(:repository_url, {:list, overrides}),
    do: normalize(:repository_url, overrides)

  def normalize(:repository_url, %Payload.ImageRepositories{overrides: overrides}),
    do: normalize(:repository_url, overrides)

  def normalize(:repository_url, overrides) when is_list(overrides) do
    case Exdock.Result.traverse(overrides, &normalize_repository/1) do
      {:ok, normalized} -> {:ok, %Payload.ImageRepositories{overrides: normalized}}
      {:error, _reason} -> invalid(:repository_url)
    end
  end

  def normalize(action, _payload), do: invalid(action)

  defp normalize_repository(%Payload.ImageRepository{image: image, url: url} = payload)
       when is_binary(image) and is_binary(url),
       do: {:ok, payload}

  defp normalize_repository({image, url}) when is_binary(image) and is_binary(url),
    do: {:ok, %Payload.ImageRepository{image: image, url: url}}

  defp normalize_repository(_value), do: {:error, :invalid}

  defp invalid(action), do: {:error, {:invalid_mutation_payload, :images, action}}
end
