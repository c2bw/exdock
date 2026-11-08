defmodule Exdock.Server.Notifier.Policy do
  @moduledoc """
  Pure notifier decisions.

  The GenServer supplies events and interprets the returned effects; this module
  contains no process, Logger, application-environment, or handler calls.
  """

  alias Exdock.Domain.{Repository, TagInfo}
  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.Event
  alias Exdock.Server.Notifier.Message

  @type status :: :enabled | :disabled
  @type effect ::
          :configure_handler
          | :remove_handler
          | {:verify_connectivity, String.t()}
          | {:system_log, Logger.level(), String.t()}
          | {:notification_log, :info | :error, atom(), String.t()}

  @spec initialize(String.t() | nil) :: {status(), String.t() | nil, [effect()]}
  def initialize(nil), do: {:disabled, nil, []}
  def initialize(url) when is_binary(url), do: {:enabled, url, [:configure_handler]}

  @spec continued(status(), String.t() | nil) :: [effect()]
  def continued(:disabled, nil),
    do: [{:system_log, :warning, "LOKI_URL not set, notification service disabled."}]

  def continued(:enabled, url) when is_binary(url), do: [{:verify_connectivity, url}]

  @spec notification(status(), atom(), term()) :: [effect()]
  def notification(:disabled, _type, _payload), do: []

  def notification(:enabled, :container_status, payload) do
    %{node: node, name: name, priority: priority, old: old, new: new} = payload

    notification_effect(
      :info,
      :container_status,
      Message.container_status(node, name, priority, old, new)
    )
  end

  def notification(:enabled, :repository_release, %Repository.Release{} = release),
    do: notification_effect(:info, :repository_release, Message.repository_release(release))

  def notification(:enabled, :image_tag, %TagInfo{} = tag_info),
    do: notification_effect(:info, :image_tag, Message.image_tag(tag_info))

  @spec job_event(status(), term()) :: [effect()]
  def job_event(
        :enabled,
        %Event{
          type: :job_finished,
          info: %Jobs.Info{name: name, automated: automated},
          result: %Jobs.Result{id: id, node: node, error: error}
        }
      )
      when not is_nil(error) do
    notification_effect(:error, :job_error, Message.job_error(name, id, automated, node, error))
  end

  def job_event(_status, _event), do: []

  @spec terminate(status(), term()) :: [effect()]
  def terminate(:enabled, reason),
    do: [{:system_log, :debug, "Notifier terminated: #{inspect(reason)}"}, :remove_handler]

  def terminate(:disabled, reason),
    do: [{:system_log, :debug, "Notifier terminated: #{inspect(reason)}"}]

  defp notification_effect(level, type, message),
    do: [{:notification_log, level, type, message}]
end
