defmodule Exdock.Docker.Local.ResponseTest do
  use ExUnit.Case, async: true

  alias DockerEngineAPI.Model
  alias Exdock.Docker.Local.Response

  test "accepts configured HTTP statuses" do
    no_content = %Tesla.Env{status: 204}
    not_modified = %Tesla.Env{status: 304}

    assert Response.expect_status({:ok, no_content}, 204) == {:ok, no_content}
    assert Response.expect_status({:ok, not_modified}, [204, 304]) == {:ok, not_modified}
  end

  test "moves unexpected HTTP responses into the error channel" do
    response = %Tesla.Env{status: 500}

    assert Response.expect_status({:ok, response}, 204) == {:error, response}
    assert Response.expect_status({:ok, :malformed}, 204) == {:error, :malformed}
  end

  test "accepts only the requested decoded model" do
    inspect_response = %Model.ContainerInspectResponse{}
    error_response = %Model.ErrorResponse{message: "missing"}

    assert Response.expect_struct({:ok, inspect_response}, Model.ContainerInspectResponse) ==
             {:ok, inspect_response}

    assert Response.expect_struct({:ok, error_response}, Model.ContainerInspectResponse) ==
             {:error, error_response}
  end

  test "rejects generated error models from otherwise successful calls" do
    error_response = %Model.ErrorResponse{message: "denied"}
    images = [%Model.ImageSummary{Id: "sha256:abc"}]

    assert Response.reject_struct({:ok, error_response}, Model.ErrorResponse) ==
             {:error, error_response}

    assert Response.reject_struct({:ok, images}, Model.ErrorResponse) == {:ok, images}
  end

  test "preserves transport errors without running success validation" do
    assert Response.normalize({:error, :closed}, fn _response -> raise "not called" end) ==
             {:error, :closed}
  end
end
