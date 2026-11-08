defmodule Exdock.Docker.Remote.ImageTest do
  use ExUnit.Case, async: true

  alias Exdock.Docker.Remote.Image
  alias Regc.Oci.Error

  test "extracts the root digest from a verified image" do
    assert Image.digest_result({:ok, %{root_ref: %{digest: "sha256:root"}}}) == "sha256:root"
  end

  test "parses valid creation dates and falls back for missing or invalid dates" do
    assert Image.creation_date_result({:ok, "2026-01-01T10:00:00Z"}) == ~U[2026-01-01 10:00:00Z]
    assert Image.creation_date_result({:ok, nil}) == ~U[1970-01-01 00:00:00Z]
    assert Image.creation_date_result({:ok, "invalid"}) == ~U[1970-01-01 00:00:00Z]
  end

  test "raises structured registry errors" do
    error = %Error{stage: :manifest, code: :not_found, message: "missing", retryable?: false, details: %{}}

    assert_raise Error, fn -> apply(Image, :digest_result, [{:error, error}]) end
    assert_raise Error, fn -> apply(Image, :creation_date_result, [{:error, error}]) end
  end
end
