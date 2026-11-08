defmodule Exdock.Server.State.Domains.Tags do
  @moduledoc "State transition boundary for registry tag metadata."

  @behaviour Exdock.Server.State.Change.Behaviour

  alias Exdock.Runtime.Mutation
  alias Exdock.Runtime.Mutation.Payload.TagsInfo, as: TagsInfoPayload
  alias Exdock.Server.State
  alias Exdock.Server.State.Change.{Outcome, Plan}
  alias Exdock.Server.State.Storage.TagsInfo

  @impl true
  def reload(%State{} = state), do: state

  @impl true
  def broadcast(%State{}), do: {nil, []}

  @impl true
  def plan(%State{} = state, %Mutation{action: :tags_info, data: %TagsInfoPayload{} = data}) do
    Plan.persisted(__MODULE__, state, %Mutation{
      domain: :tags,
      action: :tags_info,
      data: data
    })
  end

  @impl true
  def execute_persisted(
        %State{tags: %TagsInfo{} = tags} = state,
        %Mutation{action: :tags_info, data: %TagsInfoPayload{tags: tags_list}}
      ) do
    case TagsInfo.apply_updates(tags, tags_list) do
      {:ok, tags, notifications} ->
        effects = Enum.map(notifications, &{:notify_image_tag, &1})
        Outcome.planned(%{state | tags: tags}, [], effects)

      {:error, reason} ->
        {:error, reason}
    end
  end
end
