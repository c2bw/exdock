defmodule ExdockWeb.Commons.ContainerManager.LogFormatterTest do
  use ExUnit.Case, async: true

  alias ExdockWeb.Commons.ContainerManager.LogFormatter

  test "escapes HTML from container output" do
    html =
      ~s|<img src=x onerror="alert(1)"><script>alert(2)</script>&|
      |> LogFormatter.format()
      |> Phoenix.HTML.safe_to_string()

    assert html =~ ~s|&lt;img src=x onerror=&quot;alert(1)&quot;&gt;|
    assert html =~ "&lt;script&gt;alert(2)&lt;/script&gt;"
    assert html =~ "&amp;"
    refute html =~ "<img"
    refute html =~ "<script"
  end

  test "adds controlled markup for supported ANSI colors after escaping text" do
    html =
      "\e[31merror <b>unsafe</b>\e[0m"
      |> LogFormatter.format()
      |> Phoenix.HTML.safe_to_string()

    assert html == ~s|<span style="color:red">error &lt;b&gt;unsafe&lt;/b&gt;</span>|
  end

  test "removes unsupported ANSI control codes" do
    html =
      "before\e[999mafter"
      |> LogFormatter.format()
      |> Phoenix.HTML.safe_to_string()

    assert html == "beforeafter"
  end
end
