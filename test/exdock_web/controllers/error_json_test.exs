defmodule ExdockWeb.ErrorJSONTest do
  use ExdockWeb.ConnCase, async: true

  test "renders 404" do
    assert ExdockWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert ExdockWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end

  test "configures the endpoint JSON error renderer" do
    render_errors =
      :exdock
      |> Application.fetch_env!(ExdockWeb.Endpoint)
      |> Keyword.fetch!(:render_errors)

    assert render_errors[:formats][:json] == ExdockWeb.ErrorJSON
    refute Keyword.has_key?(render_errors[:formats], :Jason)
  end
end
