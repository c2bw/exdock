defmodule Exdock.Server.State.EffectRunner.Logging do
  @moduledoc false

  require Logger

  alias Exdock.Server.Logging
  alias Exdock.Server.Logging.AppendEntry
  alias Exdock.Server.State

  def run(%State{}, {:log, level, message}) when is_atom(level) and is_binary(message),
    do: Logger.log(level, message)

  def run(%State{}, {:log_entry, %AppendEntry{} = input}),
    do: Logging.add_to_log(input)
end
