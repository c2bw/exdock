defmodule Exdock.Docker.ErrorTest do
  use ExUnit.Case, async: true

  alias DockerEngineAPI.Model
  alias Exdock.AgentRuntime.Wire
  alias Exdock.Docker.Error
  alias Exdock.Protocol.Snapshot.Container

  test "keeps Docker response metadata available to callers" do
    cause = %Tesla.Env{
      status: 503,
      body: %Model.ErrorResponse{message: "daemon unavailable"}
    }

    assert %Error{
             operation: :container_start,
             status: 503,
             cause: ^cause,
             message: "daemon unavailable",
             retryable?: true
           } = Error.new(:container_start, cause)
  end

  test "classifies transient transport failures without parsing their message" do
    assert %Error{cause: :econnrefused, retryable?: true} =
             Error.new(:image_pull, :econnrefused)

    refute Error.new(:image_delete, %Tesla.Env{status: 404}).retryable?
  end

  test "renders only the operator-facing message for the protocol" do
    error = Error.new(:image_list, :timeout, message: "Docker image listing timed out")

    assert Error.to_wire(error) == "Docker image listing timed out"
    assert Error.to_wire({:not_a_docker_error, :timeout}) == {:not_a_docker_error, :timeout}
  end

  test "wire encoding renders structured errors nested in refresh results" do
    error = Error.new(:container_inspect, :timeout)
    container = %Container{id: "container-id", name: "app", is_running: false, inspect: %{}}

    assert %{
             "containers" => %{
               "errored" => [{"timeout", %{"id" => "container-id"}}]
             }
           } =
             Wire.encode_result(
               "node_refresh",
               {%{ok: [], errored: [{error, container}]}, %{ok: [], errored: []}}
             )
  end
end
