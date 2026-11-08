defmodule Exdock.URLTest do
  use ExUnit.Case, async: true

  alias Exdock.URL

  test "normalizes external URLs without a scheme" do
    assert URL.normalize_external("example.com") == "https://example.com"
  end

  test "preserves HTTP URLs and empty values" do
    assert URL.normalize_external("http://example.com") == "http://example.com"
    assert URL.normalize_external("https://example.com") == "https://example.com"
    assert URL.normalize_external("") == ""
  end
end
