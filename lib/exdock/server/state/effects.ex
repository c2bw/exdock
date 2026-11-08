defmodule Exdock.Server.State.Effects do
  @moduledoc """
  Contract for side effects emitted by state-transition orchestration.

  The production interpreter is configured separately so reducers can compile
  and be tested without depending on PubSub, jobs, logging, or notifications.
  """

  alias Exdock.Domain.TagInfo
  alias Exdock.Server.State.Domain, as: StateDomain
  alias Exdock.Server.Jobs
  alias Exdock.Server.Logging.AppendEntry
  alias Exdock.Runtime.DomainCatalog

  @type effect ::
          {:broadcast, StateDomain.name(), keyword() | nil}
          | {:broadcast_projection, DomainCatalog.derived_projection()}
          | {:schedule_automation, Exdock.Server.State.PeriodicJob.t()}
          | {:job_info, Jobs.Message.t()}
          | {:job_update, Jobs.Update.t()}
          | {:job_result, Jobs.Result.t()}
          | {:server_command, term(), keyword()}
          | {:container_status, Exdock.Server.State.ContainerStatus.transition()}
          | {:log, Logger.level(), String.t()}
          | {:log_entry, AppendEntry.t()}
          | {:notify_image_tag, TagInfo.t()}

  @spec broadcasts([StateDomain.name()]) :: [effect()]
  def broadcasts(domains) when is_list(domains) do
    Enum.map(domains, &{:broadcast, &1, nil}) ++ derived_broadcasts(domains)
  end

  @spec derived_broadcasts(Enumerable.t()) :: [effect()]
  def derived_broadcasts(domains) do
    domains
    |> DomainCatalog.derived_projections()
    |> Enum.map(&{:broadcast_projection, &1})
  end
end
