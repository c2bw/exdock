defmodule Exdock.Server.Notifier.Handler do
  @moduledoc """
  Owns configuration and lifecycle operations for the notifier's Loki handler.
  """

  require Logger

  @glasgow_handler :glasgow

  @spec configured_url() :: String.t() | nil
  def configured_url do
    :exdock
    |> Application.get_env(:logger, [])
    |> configured_url()
  end

  @spec configured_url(term()) :: String.t() | nil
  def configured_url(handlers), do: url_from_config(handlers)

  @spec url_from_config(term()) :: String.t() | nil
  def url_from_config(handlers) when is_list(handlers) do
    Enum.find_value(handlers, &handler_url/1)
  end

  def url_from_config(_handlers), do: nil

  @spec configure() :: :ok | {:error, term()}
  def configure do
    case Logger.add_handlers(:exdock) do
      :ok ->
        Logger.debug("Notifier handler configured.")
        :ok

      {:error, error} ->
        Logger.error("Notifier handler configuration error: #{inspect(error)}")
        {:error, error}
    end
  end

  @spec verify_connectivity(String.t()) :: :ok
  def verify_connectivity(url) when is_binary(url) do
    case Glasgow.Loki.Client.ready(url) do
      {:ok, status} -> Logger.info("Loki readiness status: #{status}")
      {:error, status, error} -> Logger.warning("Loki not reachable: #{status} - #{error}")
    end

    :ok
  end

  @spec remove() :: :ok
  def remove do
    case :logger.remove_handler(@glasgow_handler) do
      :ok -> Logger.debug("Notifier handler removed.")
      {:error, {:not_found, @glasgow_handler}} -> Logger.debug("Notifier handler was already removed.")
      {:error, reason} -> Logger.error("Failed to remove notifier handler: #{inspect(reason)}")
    end

    :ok
  end

  defp handler_url({:handler, @glasgow_handler, _backend, %{config: %{url: url}}})
       when is_binary(url) or is_nil(url),
       do: url

  defp handler_url(_handler), do: nil
end
