defmodule Exdock.Server.Connection.Handshake do
  @moduledoc """
  Pure validation for the server side of the agent handshake.

  Socket registration and protocol effects remain in the connection handler;
  this module owns only credential, release, and runtime-bundle validation.
  """

  alias Exdock.Protocol.Compatibility

  @type validation_error :: :invalid_auth | {:version_requirement, String.t()}

  @spec minimum_client_version() :: String.t()
  def minimum_client_version, do: Compatibility.agent_requirement()

  @spec validate_client(term(), term(), term()) :: :ok | {:error, validation_error()}
  def validate_client(client_version, expected_auth_token, presented_auth_token) do
    with :ok <- require_supported_version(client_version),
         true <- valid_auth_token?(expected_auth_token, presented_auth_token) do
      :ok
    else
      false -> {:error, :invalid_auth}
      {:error, _reason} = error -> error
    end
  end

  @spec ready?(String.t(), String.t() | nil, term(), term()) :: boolean()
  def ready?(expected_version, expected_digest, bundle_version, digest)
      when is_binary(expected_version) and is_binary(expected_digest) do
    bundle_version == expected_version and digest == expected_digest
  end

  def ready?(_expected_version, _expected_digest, _bundle_version, _digest), do: false

  @spec valid_auth_token?(term(), term()) :: boolean()
  def valid_auth_token?(expected, presented)
      when is_binary(expected) and is_binary(presented) and
             byte_size(expected) == byte_size(presented) do
    Plug.Crypto.secure_compare(expected, presented)
  end

  def valid_auth_token?(_expected, _presented), do: false

  defp require_supported_version(client_version) when is_binary(client_version) do
    requirement = minimum_client_version()

    if Version.match?(client_version, requirement) do
      :ok
    else
      {:error, {:version_requirement, requirement}}
    end
  end

  defp require_supported_version(_client_version),
    do: {:error, {:version_requirement, minimum_client_version()}}
end
