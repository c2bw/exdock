defmodule Exdock.Runtime.EventSink do
  @moduledoc "Contract for publishing public runtime and operation events."

  @callback publish(atom() | {:node, String.t()}, term()) :: :ok
  @callback operation_accepted(Ecto.UUID.t(), atom()) :: :ok
  @callback operation_finished(Ecto.UUID.t(), atom(), term()) :: :ok
end
