defmodule Exdock.Client.Connection.Session do
  @moduledoc """
  Pure lifecycle state machine for the standalone agent connection.

  The TCP client owns sockets and timer references. This module owns only valid
  phase transitions and reconnect policy, so transport resources cannot imply a
  contradictory logical connection state.
  """

  @type phase :: :disconnected | :connecting | :authenticating | :initializing | :ready
  @type event :: :connect | :socket_connected | :runtime_bundle_received | :ready | :disconnect

  @enforce_keys [:phase, :reconnect_enabled]
  defstruct phase: :disconnected, reconnect_enabled: true

  @type t :: %__MODULE__{
          phase: phase(),
          reconnect_enabled: boolean()
        }

  @spec new() :: t()
  def new, do: %__MODULE__{phase: :disconnected, reconnect_enabled: true}

  @spec transition(t(), event()) :: {:ok, t()} | {:error, {:invalid_transition, phase(), event()}}
  def transition(%__MODULE__{phase: :disconnected} = session, :connect),
    do: {:ok, %{session | phase: :connecting}}

  def transition(%__MODULE__{phase: :connecting} = session, :socket_connected),
    do: {:ok, %{session | phase: :authenticating}}

  def transition(%__MODULE__{phase: :authenticating} = session, :runtime_bundle_received),
    do: {:ok, %{session | phase: :initializing}}

  def transition(%__MODULE__{phase: :initializing} = session, :ready),
    do: {:ok, %{session | phase: :ready}}

  def transition(%__MODULE__{} = session, :disconnect),
    do: {:ok, %{session | phase: :disconnected}}

  def transition(%__MODULE__{phase: phase}, event),
    do: {:error, {:invalid_transition, phase, event}}

  @spec disable_reconnect(t()) :: t()
  def disable_reconnect(%__MODULE__{} = session),
    do: %{session | reconnect_enabled: false}

  @spec connectable?(t()) :: boolean()
  def connectable?(%__MODULE__{phase: :disconnected}), do: true
  def connectable?(%__MODULE__{}), do: false

  @spec socket_open?(t()) :: boolean()
  def socket_open?(%__MODULE__{phase: phase}),
    do: phase in [:authenticating, :initializing, :ready]

  @spec reconnect_enabled?(t()) :: boolean()
  def reconnect_enabled?(%__MODULE__{reconnect_enabled: reconnect_enabled}),
    do: reconnect_enabled

  @spec in_phase?(t(), phase()) :: boolean()
  def in_phase?(%__MODULE__{phase: phase}, phase), do: true
  def in_phase?(%__MODULE__{}, _phase), do: false
end
