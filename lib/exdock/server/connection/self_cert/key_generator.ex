defmodule Exdock.Server.Connection.SelfCert.KeyGenerator do
  @moduledoc "Crypto boundary used by self-signed certificate construction."

  @callback generate_rsa_key(pos_integer(), pos_integer()) :: {:ok, term()} | {:error, term()}
  @callback public_key(term()) :: term()
  @callback serial_number() :: pos_integer()
end
