defmodule ExdockWeb.ClientIp do
  @moduledoc """
  Resolves the client IP used for security-sensitive request accounting.

  Forwarded addresses are considered only when the connection's immediate peer
  is listed in `:trusted_proxy_ips`. The forwarded chain is read from right to
  left so trusted intermediary proxies are skipped and the nearest untrusted
  address is selected.
  """

  import Plug.Conn, only: [get_req_header: 2]

  @type ip_address :: :inet.ip_address()

  @spec from_conn(Plug.Conn.t()) :: ip_address()
  def from_conn(conn) do
    from_conn(conn, Application.get_env(:exdock, :trusted_proxy_ips, []))
  end

  @spec from_conn(Plug.Conn.t(), [ip_address()]) :: ip_address()
  def from_conn(%Plug.Conn{remote_ip: remote_ip} = conn, trusted_proxy_ips) when is_list(trusted_proxy_ips) do
    trusted_proxy_ips = MapSet.new(trusted_proxy_ips)

    if MapSet.member?(trusted_proxy_ips, remote_ip) do
      forwarded_client_ip(conn, trusted_proxy_ips) || remote_ip
    else
      remote_ip
    end
  end

  defp forwarded_client_ip(conn, trusted_proxy_ips) do
    with [header] <- get_req_header(conn, "x-forwarded-for"),
         {:ok, forwarded_ips} <- parse_forwarded_for(header) do
      forwarded_ips
      |> Enum.reverse()
      |> Enum.find(&(not MapSet.member?(trusted_proxy_ips, &1)))
    else
      _missing_or_invalid -> nil
    end
  end

  defp parse_forwarded_for(header) do
    result =
      header
      |> String.split(",", trim: true)
      |> Exdock.Result.traverse(fn address ->
        case address |> String.trim() |> String.to_charlist() |> :inet.parse_address() do
          {:ok, ip} -> {:ok, ip}
          {:error, reason} -> {:error, reason}
        end
      end)

    case result do
      {:ok, []} -> :error
      {:ok, addresses} -> {:ok, addresses}
      {:error, _reason} -> :error
    end
  end
end
