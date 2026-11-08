defmodule Exdock.Server.Jobs.Submission do
  @moduledoc "Interprets normalized job plans at the dispatcher process boundary."

  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.Plan

  @spec submit(Plan.t()) :: :ok
  def submit(%Plan{} = plan) do
    case Plan.submission(plan) do
      :empty -> :ok
      {:one, work} -> Jobs.add(work)
      {:batch, details} -> Jobs.add(details)
      {:individual, details} -> Enum.each(details, &Jobs.add/1)
    end
  end
end
