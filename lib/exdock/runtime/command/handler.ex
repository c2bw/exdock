defmodule Exdock.Runtime.Command.Handler do
  @moduledoc false

  alias Exdock.Server.Jobs.Plan
  alias Exdock.Server.State

  @callback kind(struct()) :: atom()
  @callback normalize(struct()) :: {:ok, struct()} | {:error, term()}
  @callback execute(State.t(), struct()) ::
              {:work, Plan.source()} | {:state, State.t()} | {:error, term()}
end
