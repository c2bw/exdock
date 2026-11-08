defmodule Exdock.Runtime.MutationContract.Tags do
  @moduledoc false

  alias Exdock.Domain
  alias Exdock.Runtime.Mutation.Payload

  @spec normalize(term(), term()) :: {:ok, term()} | {:error, term()}
  def normalize(:tags_info, tags) when is_list(tags),
    do: normalize(:tags_info, %Payload.TagsInfo{tags: tags})

  def normalize(:tags_info, %Payload.TagsInfo{tags: tags} = payload) when is_list(tags) do
    if Enum.all?(tags, &match?(%Domain.TagInfo{}, &1)),
      do: {:ok, payload},
      else: invalid(:tags_info)
  end

  def normalize(action, _payload), do: invalid(action)

  defp invalid(action), do: {:error, {:invalid_mutation_payload, :tags, action}}
end
