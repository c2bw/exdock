defmodule Exdock.Server.Notifier.HandlerTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Notifier.Handler

  test "extracts the Glasgow URL from logger handler configuration" do
    handlers = [
      {:handler, :console, Logger, %{config: %{url: "ignore"}}},
      {:handler, :glasgow, Glasgow, %{config: %{url: "http://loki:3100"}}}
    ]

    assert Handler.url_from_config(handlers) == "http://loki:3100"
  end

  test "returns nil for disabled or malformed configurations" do
    assert Handler.url_from_config([]) == nil
    assert Handler.url_from_config(nil) == nil
    assert Handler.url_from_config([{:handler, :glasgow, Glasgow, %{config: %{url: nil}}}]) == nil
    assert Handler.url_from_config([{:handler, :glasgow, Glasgow, %{config: %{}}}]) == nil
  end
end
