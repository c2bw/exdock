defmodule Exdock.Server.State.EffectRunner.Notifications do
  @moduledoc false

  alias Exdock.Domain.TagInfo
  alias Exdock.Server.{Logging, Notifier}
  alias Exdock.Server.Logging.AppendEntry
  alias Exdock.Server.State

  def run(
        %State{},
        {:container_status,
         %{
           node: node,
           name: name,
           priority: priority,
           previous: previous,
           current: current,
           notify?: notify?
         }}
      ) do
    Logging.add_to_log(
      AppendEntry.new(
        :container_status,
        {node, name, previous || :new_container, current}
      )
    )

    if notify? do
      Notifier.notify_container_status(node, name, priority, previous, current)
    end
  end

  def run(%State{}, {:notify_image_tag, %TagInfo{} = tag_info}),
    do: Notifier.notify_image_tag(tag_info)
end
