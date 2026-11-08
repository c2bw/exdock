defmodule Exdock.Status.Dashboard do
  @moduledoc "Public contract for the operator-facing job status dashboard."

  alias Exdock.Status.Dashboard.Row
  alias Exdock.Server.Jobs.Catalog

  @type job_name :: Catalog.job_name()

  @type entries :: %{term() => Row.t()}
  @type t :: %{required(job_name()) => entries()}
end
