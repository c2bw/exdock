defmodule Exdock.Protocol.ExecutionBudget do
  @moduledoc "Shared Docker request and command-liveness budgets for server and agent."

  @spec request_timeout() :: pos_integer()
  def request_timeout, do: :timer.minutes(30)

  @spec activity_interval() :: pos_integer()
  def activity_interval, do: :timer.seconds(30)

  @doc "Allows the request deadline plus delivery time without command activity."
  @spec result_timeout() :: pos_integer()
  def result_timeout, do: request_timeout() + :timer.minutes(1)
end
