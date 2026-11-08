defmodule Exdock.Database.Vault do
  use Cloak.Vault, otp_app: :exdock

  @impl GenServer
  def init(config) do
    config =
      Keyword.put(config, :ciphers,
        default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: vault_key!(:db_vault_key), iv_length: 12},
        json_library: Jason
      )

    {:ok, config}
  end

  defp vault_key!(env_key) do
    Application.get_env(:exdock, env_key) |> Base.decode64!()
  end
end
