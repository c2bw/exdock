defmodule Exdock.Encrypted.Binary do
  use Cloak.Ecto.Binary, vault: Exdock.Database.Vault
end
