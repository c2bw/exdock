defmodule Exdock.Client.Connection.Timer do
  @moduledoc "Process timer boundary used by the persistent client connection."

  @callback heartbeat(non_neg_integer()) :: reference()
  @callback reconnect(non_neg_integer()) :: reference()
  @callback cancel(reference()) :: non_neg_integer() | false

  @behaviour __MODULE__

  @impl true
  def heartbeat(interval), do: Process.send_after(self(), :heartbeat, interval)

  @impl true
  def reconnect(interval), do: :erlang.start_timer(interval, self(), :try_reconnect)

  @impl true
  def cancel(timer), do: Process.cancel_timer(timer)
end
