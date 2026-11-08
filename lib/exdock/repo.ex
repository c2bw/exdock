defmodule Exdock.Repo do
  @moduledoc """
  Ecto repository for Exdock's SQLite persistence.

  The server state owns the live cluster snapshot; this repo stores the durable
  subset used to rebuild settings, users, repositories, images, and containers
  across restarts.
  """

  use Ecto.Repo,
    otp_app: :exdock,
    adapter: Ecto.Adapters.SQLite3
end
