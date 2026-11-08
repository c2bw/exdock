defmodule Exdock.Server.Connection.Utils do
  @doc """
  Return the string representation of the client's address and port.
  """
  @spec socket_address(:ssl.sslsocket()) :: String.t()
  def socket_address(socket) do
    case client_info(socket) do
      nil -> ""
      %{address: address, port: port} -> "#{address}:#{port}"
    end
  end

  @doc """
  Return the client's address and port.
  """
  @spec client_info(:ssl.sslsocket()) :: map() | nil
  def client_info(socket) do
    case peername(socket) do
      {:ok, {address, port}} -> %{address: format_address(address), port: port}
      {:error, _reason} -> nil
    end
  end

  defp peername(socket) do
    :ssl.peername(socket)
  rescue
    _exception -> {:error, :invalid_socket}
  catch
    _kind, _reason -> {:error, :invalid_socket}
  end

  defp format_address(address) when is_tuple(address) do
    address
    |> :inet.ntoa()
    |> to_string()
  end
end
