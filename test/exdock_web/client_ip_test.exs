defmodule ExdockWeb.ClientIpTest do
  use ExdockWeb.ConnCase, async: true

  alias ExdockWeb.ClientIp

  test "ignores forwarded addresses from an untrusted peer", %{conn: conn} do
    proxy_ip = {10, 0, 0, 5}

    conn = %{conn | remote_ip: proxy_ip}
    conn = put_req_header(conn, "x-forwarded-for", "198.51.100.20")

    assert ClientIp.from_conn(conn, []) == proxy_ip
  end

  test "selects the nearest untrusted address behind trusted proxies", %{conn: conn} do
    edge_proxy = {10, 0, 0, 5}
    internal_proxy = {10, 0, 0, 6}

    conn = %{conn | remote_ip: edge_proxy}
    conn = put_req_header(conn, "x-forwarded-for", "198.51.100.20, 10.0.0.6")

    assert ClientIp.from_conn(conn, [edge_proxy, internal_proxy]) == {198, 51, 100, 20}

    other_conn = put_req_header(conn, "x-forwarded-for", "198.51.100.21, 10.0.0.6")

    refute ClientIp.from_conn(conn, [edge_proxy, internal_proxy]) ==
             ClientIp.from_conn(other_conn, [edge_proxy, internal_proxy])
  end

  test "falls back to the peer address for malformed forwarded chains", %{conn: conn} do
    proxy_ip = {10, 0, 0, 5}

    conn = %{conn | remote_ip: proxy_ip}
    conn = put_req_header(conn, "x-forwarded-for", "not-an-ip")

    assert ClientIp.from_conn(conn, [proxy_ip]) == proxy_ip
  end
end
