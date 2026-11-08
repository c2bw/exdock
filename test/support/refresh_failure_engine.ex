defmodule Exdock.TestSupport.RefreshFailureEngine do
  @moduledoc false

  def connect, do: :connection
  def list_containers(:connection, true, _opts), do: {:error, :econnrefused}
  def list_containers(:connection, false, _opts), do: {:ok, %{ok: [], errored: []}}
  def list_images(:connection), do: {:error, :timeout}
  def start_container(:connection, _id), do: {:ok, :started}
end
