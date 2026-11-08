defmodule Exdock.ClientLib.Jobs.ActionRunner do
  @moduledoc """
  Normalizes simple Docker actions to the client job result contract.
  """

  require Logger
  alias Exdock.ClientLib.Utils
  alias Exdock.ClientLib.Jobs.Context

  @spec run(
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          (module(), term() -> term()),
          Context.t()
        ) ::
          {:ok, String.t()} | {:error, term(), String.t()}
  def run(in_progress, completed, failed, resource, identifier, action, context)
      when is_binary(identifier) and is_function(action, 2) do
    Logger.info("#{in_progress} #{resource} [#{identifier}]")
    {engine, conn} = Context.connect(context)

    case action.(engine, conn) do
      {:ok, _response} ->
        Logger.info("OK | #{completed} #{resource} [#{identifier}]")
        {:ok, identifier}

      {:error, error} ->
        Logger.error("#{failed} #{resource} [#{identifier}]: #{Utils.error_message(error)}")
        {:error, error, identifier}
    end
  end
end
