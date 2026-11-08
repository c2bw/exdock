defmodule Exdock.Protocol.Contract do
  @moduledoc """
  Canonical wire contract shared by the Exdock server and standalone client.

  The contract owns protocol versioning, message identifiers, frame encoding,
  and fallible Erlang-term decoding. Endpoint codecs remain responsible for
  validating which payload shapes are allowed at their respective trust
  boundaries.
  """

  alias Exdock.Protocol.Compatibility

  @current_version Compatibility.wire_version()
  @message_types %{
    heartbeat: 1,
    error: 9,
    hello: 10,
    runtime_bundle: 11,
    ready: 12,
    command: 13,
    progress: 14,
    result: 15,
    resource_sample: 16
  }
  @message_names Map.new(@message_types, fn {name, type} -> {type, name} end)

  @type message_name ::
          :heartbeat
          | :error
          | :hello
          | :runtime_bundle
          | :ready
          | :command
          | :progress
          | :result
          | :resource_sample

  @type decode_error ::
          :version_too_new
          | :version_too_old
          | :unknown_message_type
          | :malformed_message

  @spec current_version() :: pos_integer()
  def current_version, do: @current_version

  @spec message_types() :: %{message_name() => pos_integer()}
  def message_types, do: @message_types

  @spec encode_frame(message_name(), binary()) :: binary()
  def encode_frame(message_name, payload) when is_binary(payload) do
    <<@current_version::8, Map.fetch!(@message_types, message_name)::8, payload::binary>>
  end

  @spec encode_term_frame(message_name(), term()) :: binary()
  def encode_term_frame(message_name, term) do
    encode_frame(message_name, :erlang.term_to_binary(term))
  end

  @spec decode_frame(binary()) :: {:ok, message_name(), binary()} | {:error, decode_error()}
  def decode_frame(<<version::8, type::8, payload::binary>>) do
    with :ok <- validate_version(version),
         {:ok, message_name} <- fetch_message_name(type) do
      {:ok, message_name, payload}
    end
  end

  def decode_frame(_malformed_frame), do: {:error, :malformed_message}

  @spec decode_term(binary(), [:safe] | []) :: {:ok, term()} | :error
  def decode_term(payload, options \\ []) when options in [[], [:safe]] do
    {:ok, :erlang.binary_to_term(payload, options)}
  rescue
    ArgumentError -> :error
  end

  defp validate_version(@current_version), do: :ok
  defp validate_version(version) when version > @current_version, do: {:error, :version_too_new}
  defp validate_version(version) when version < @current_version, do: {:error, :version_too_old}

  defp fetch_message_name(type) do
    case Map.fetch(@message_names, type) do
      {:ok, message_name} -> {:ok, message_name}
      :error -> {:error, :unknown_message_type}
    end
  end
end
