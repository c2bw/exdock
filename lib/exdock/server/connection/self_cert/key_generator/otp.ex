defmodule Exdock.Server.Connection.SelfCert.KeyGenerator.OTP do
  @moduledoc "OTP public-key implementation of the self-certificate crypto boundary."

  @behaviour Exdock.Server.Connection.SelfCert.KeyGenerator

  require Record

  Record.defrecordp(
    :rsa_private_key,
    :RSAPrivateKey,
    Record.extract(:RSAPrivateKey, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  Record.defrecordp(
    :rsa_public_key,
    :RSAPublicKey,
    Record.extract(:RSAPublicKey, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  @impl true
  def generate_rsa_key(key_size, exponent) do
    {:ok, :public_key.generate_key({:rsa, key_size, exponent})}
  rescue
    FunctionClauseError -> {:error, :not_supported}
  end

  @impl true
  def public_key(rsa_private_key(modulus: modulus, publicExponent: exponent)),
    do: rsa_public_key(modulus: modulus, publicExponent: exponent)

  @impl true
  def serial_number do
    <<serial::unsigned-64>> = :crypto.strong_rand_bytes(8)
    max(serial, 1)
  end
end
