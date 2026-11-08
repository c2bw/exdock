defmodule Exdock.Server.State.EffectRunner.Jobs do
  @moduledoc false

  alias Exdock.Server.Jobs
  alias Exdock.Server.State

  def run(%State{}, {:job_info, %Jobs.Message{} = message}), do: Jobs.info_message(message)
  def run(%State{}, {:job_update, %Jobs.Update{} = update}), do: Jobs.job_update(update)
  def run(%State{}, {:job_result, %Jobs.Result{} = result}), do: Jobs.job_result(result)
end
