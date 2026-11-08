defmodule Exdock.Client.Connection.State do
  @moduledoc """
  Typed transport and lifecycle state shared by the standalone TCP client.

  Keeping this struct outside the GenServer module lets handshake, transition,
  and effect modules depend on the state contract without depending back on the
  process that orchestrates them.
  """

  alias Exdock.Client.Connection.{RuntimeExecutor, Session, Timer, Transport}

  defstruct host: nil,
            port: nil,
            socket: nil,
            client_name: nil,
            auth_key: nil,
            session: %Session{phase: :disconnected, reconnect_enabled: true},
            reconnect_timer: nil,
            heartbeat_timer: nil,
            transport: Transport,
            timer: Timer,
            runtime_executor: RuntimeExecutor

  @type t :: %__MODULE__{
          host: :inet.hostname() | :inet.ip_address() | nil,
          port: :inet.port_number() | nil,
          socket: :ssl.sslsocket() | term() | nil,
          client_name: String.t() | nil,
          auth_key: String.t() | nil,
          session: Session.t(),
          reconnect_timer: reference() | nil,
          heartbeat_timer: reference() | nil,
          transport: module(),
          timer: module(),
          runtime_executor: module()
        }

  @spec new(keyword()) :: t()
  def new(attributes \\ []) when is_list(attributes), do: struct!(__MODULE__, attributes)
end
