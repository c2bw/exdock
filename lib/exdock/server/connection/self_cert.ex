defmodule Exdock.Server.Connection.SelfCert do
  @moduledoc "Generates the ephemeral self-signed certificate used by the agent listener."

  require Logger

  alias Exdock.Server.Connection.SelfCert.{KeyGenerator, Profile}

  @default_name "Self-signed Exdock certificate"
  @default_hostnames ["localhost"]

  @spec generate() :: {binary(), {:RSAPrivateKey, binary()}}
  def generate do
    started_at = System.monotonic_time(:millisecond)
    Logger.info("Generating self-signed certificate..")
    {certificate, private_key} = certificate_and_key(2048, @default_name, @default_hostnames)
    key_der = :public_key.der_encode(:RSAPrivateKey, private_key)
    elapsed = System.monotonic_time(:millisecond) - started_at
    Logger.info("Generated certificates in #{elapsed}ms")
    {certificate, {:RSAPrivateKey, key_der}}
  end

  @spec certificate_and_key(pos_integer(), String.t(), [String.t()], keyword()) ::
          {binary(), term()}
  def certificate_and_key(key_size, name, hostnames, opts \\ [])
      when is_integer(key_size) and key_size > 0 and is_binary(name) and is_list(hostnames) and
             is_list(opts) do
    key_generator = Keyword.get(opts, :key_generator, KeyGenerator.OTP)
    clock = Keyword.get(opts, :clock, &Date.utc_today/0)

    private_key = generate_key!(key_generator, key_size)
    public_key = key_generator.public_key(private_key)
    serial = Keyword.get_lazy(opts, :serial_number, &key_generator.serial_number/0)
    today = clock.()

    certificate =
      public_key
      |> Profile.build(name, hostnames, today, serial)
      |> :public_key.pkix_sign(private_key)

    {certificate, private_key}
  end

  defp generate_key!(key_generator, key_size) do
    case key_generator.generate_rsa_key(key_size, 65_537) do
      {:ok, key} ->
        key

      {:error, :not_supported} ->
        raise "failed to generate an RSA key pair: RSA key generation is not supported by this Erlang/OTP runtime"

      {:error, reason} ->
        raise "failed to generate an RSA key pair: #{inspect(reason)}"
    end
  end
end
