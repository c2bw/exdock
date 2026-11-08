defmodule Exdock.Server.Notifier.Message do
  @moduledoc """
  Formats structured domain events for notification delivery.
  """

  alias Exdock.Datetime
  alias Exdock.Domain.Repository
  alias Exdock.Domain.TagInfo

  @spec job_error(atom(), String.t(), boolean(), term(), term()) :: String.t()
  def job_error(name, id, automated, node, error) do
    "job_name=#{name} job_id=#{id} automated=#{automated} node=#{node} error=\"#{error}\""
  end

  @spec container_status(term(), String.t(), atom(), term(), term()) :: String.t()
  def container_status(node, name, priority, old_status, new_status) do
    "node=#{node} container=#{name} priority=#{priority} changed from old=#{old_status} new=#{new_status}"
  end

  @spec repository_release(Repository.Release.t()) :: String.t()
  def repository_release(%Repository.Release{
        name: name,
        version: version,
        release_url: release_url,
        time_released: time_released
      }) do
    "name=#{name} version=#{version} release_url=#{release_url} time_released=\"#{Datetime.utc_to_timezone(time_released)}\""
  end

  @spec image_tag(TagInfo.t()) :: String.t()
  def image_tag(%TagInfo{
        tag: tag,
        platform: platform,
        latest_date: date,
        latest_digest: digest
      }) do
    "tag=#{tag} platform=#{platform} date=\"#{Datetime.utc_to_timezone(date)}\" digest=#{digest}"
  end
end
