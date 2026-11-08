defmodule Exdock.Server.Connection.Session do
  @moduledoc """
  Pure handshake lifecycle state for one server-side agent session.

  Socket ownership, timers, remote-job correlation, registration, and logging
  remain separate concerns. This module makes valid protocol phases explicit
  and rejects messages that do not belong to the current phase.
  """

  alias Exdock.Server.Connection.WireMessage

  @type phase :: :awaiting_hello | :awaiting_ready | :ready

  @enforce_keys [:phase]
  defstruct phase: :awaiting_hello,
            client_name: nil,
            bundle_digest: nil

  @type t :: %__MODULE__{
          phase: phase(),
          client_name: String.t() | nil,
          bundle_digest: String.t() | nil
        }

  @type route ::
          :heartbeat
          | {:authenticate, String.t(), String.t(), String.t()}
          | {:initialize, String.t(), String.t(), map()}
          | {:job_result, WireMessage.t()}
          | {:client_message, term()}
          | {:stop, term()}

  @spec new() :: t()
  def new, do: %__MODULE__{phase: :awaiting_hello}

  @spec route(t(), term()) :: route()
  def route(%__MODULE__{}, {:heartbeat, _payload}), do: :heartbeat

  def route(%__MODULE__{}, {:error, reason})
      when reason in [:version_too_old, :version_too_new, :unknown_message_type, :malformed_message],
      do: {:stop, reason}

  def route(
        %__MODULE__{phase: :awaiting_hello},
        {:hello, client_version, auth_key, client_name}
      ),
      do: {:authenticate, client_version, auth_key, client_name}

  def route(%__MODULE__{phase: :awaiting_ready}, {:ready, bundle_version, digest, metadata}),
    do: {:initialize, bundle_version, digest, metadata}

  def route(
        %__MODULE__{phase: :ready},
        {:client_message, %WireMessage{type: :result} = message}
      ),
      do: {:job_result, message}

  def route(%__MODULE__{phase: :ready}, {:client_message, message}),
    do: {:client_message, message}

  def route(%__MODULE__{phase: :awaiting_hello}, _message), do: {:stop, :unauthorized}
  def route(%__MODULE__{}, _message), do: {:stop, :unexpected_message}

  @spec trust(t()) :: :untrusted | :authenticated
  def trust(%__MODULE__{phase: :awaiting_hello}), do: :untrusted
  def trust(%__MODULE__{}), do: :authenticated

  @spec identify(t(), String.t()) :: t()
  def identify(%__MODULE__{phase: :awaiting_hello} = session, client_name)
      when is_binary(client_name),
      do: %{session | client_name: client_name}

  @spec authenticate(t()) :: t()
  def authenticate(%__MODULE__{phase: :awaiting_hello, client_name: client_name} = session)
      when is_binary(client_name),
      do: %{session | phase: :awaiting_ready}

  @spec offer_bundle(t(), String.t()) :: t()
  def offer_bundle(%__MODULE__{phase: :awaiting_ready} = session, digest)
      when is_binary(digest),
      do: %{session | bundle_digest: digest}

  @spec initialize(t()) :: t()
  def initialize(%__MODULE__{phase: :awaiting_ready, bundle_digest: digest} = session)
      when is_binary(digest),
      do: %{session | phase: :ready}

  @spec ready?(t()) :: boolean()
  def ready?(%__MODULE__{phase: :ready}), do: true
  def ready?(%__MODULE__{}), do: false

  @spec registered?(t()) :: boolean()
  def registered?(%__MODULE__{phase: phase}), do: phase in [:awaiting_ready, :ready]
end
