defmodule Exdock.Server.Connection.HandlerTest do
  use ExUnit.Case, async: true

  alias Exdock.Protocol.Messages.JobResult
  alias Exdock.Protocol.Command
  alias Exdock.Server.Connection.Handler
  alias Exdock.Server.Connection.Handler.State, as: HandlerState
  alias Exdock.Server.Connection.Handshake
  alias Exdock.Server.Connection.RemoteJobs
  alias Exdock.Server.Connection.Session
  alias Exdock.Server.Connection.WireMessage
  alias Exdock.Server.Jobs.{Job, Result}

  test "initialization timeout stops a client awaiting runtime readiness" do
    state = %HandlerState{session: authenticated_session("node-a")}

    assert {:stop, :client_init_timeout, ^state} = Handler.handle_info(:is_client_ready, state)
  end

  test "initialization timeout keeps a fully initialized client connected" do
    state = %HandlerState{session: ready_session("node-a")}

    assert {:noreply, ^state} = Handler.handle_info(:is_client_ready, state)
  end

  test "auth token comparison accepts only equal binary tokens" do
    assert Handshake.valid_auth_token?("same-token", "same-token")
    refute Handshake.valid_auth_token?("same-token", "other-toke")
    refute Handshake.valid_auth_token?("same-token", "short")
    refute Handshake.valid_auth_token?("same-token", nil)
  end

  test "handshake validates release, credentials, and bundle acknowledgement" do
    assert :ok = Handshake.validate_client("1.2.0", "same-token", "same-token")
    assert {:error, :invalid_auth} = Handshake.validate_client("1.2.0", "same-token", "wrong-token")

    assert {:error, {:version_requirement, "~> 1.2.0"}} =
             Handshake.validate_client("2.0.0", "same-token", "same-token")

    assert Handshake.ready?("1", "digest", "1", "digest")
    refute Handshake.ready?("1", "digest", "2", "digest")
    refute Handshake.ready?("1", "digest", "1", "other")
  end

  test "accepts a result only for a job dispatched on the authenticated connection" do
    job = %Job{id: "job-id", name: :container_start, parameters: ["container-id"], data: %{source: :test}}

    state =
      handler_state("node-a")
      |> Handler.track_dispatched_job(job)

    result = wire_result("job-id", :container_start, "node-a")

    assert {:ok, accepted_state, ^job} =
             Handler.correlate_wire_result(state, result)

    assert accepted_state.remote_jobs.entries == %{}
    assert {:error, :unknown_job} = Handler.correlate_wire_result(accepted_state, result)
  end

  test "refresh generations follow dispatch order and survive reverse result order" do
    first = %Job{id: "first-refresh", name: :node_refresh}
    second = %Job{id: "second-refresh", name: :node_refresh}
    state = handler_state("node-a") |> Handler.track_dispatched_job(first) |> Handler.track_dispatched_job(second)
    assert {:ok, state, newer} = Handler.correlate_wire_result(state, wire_result(second.id, :node_refresh, "node-a"))
    assert {:ok, state, older} = Handler.correlate_wire_result(state, wire_result(first.id, :node_refresh, "node-a"))
    assert is_integer(older.refresh_generation)
    assert older.refresh_generation < newer.refresh_generation
    assert state.remote_jobs.entries == %{}
  end

  test "expires a dispatched job into a terminal timeout result" do
    state =
      handler_state("node-a")
      |> Handler.track_dispatched_job(%Job{id: "job-id", name: :container_start})

    token = state.remote_jobs.entries["job-id"].token

    assert {:ok, expired_state,
            %JobResult{
              job: %Job{id: "job-id", name: :container_start},
              result: %Result{
                id: "job-id",
                node: "node-a",
                data: nil,
                error: :client_job_timeout
              }
            }} = Handler.expire_dispatched_job(state, "job-id", token)

    assert expired_state.remote_jobs.entries == %{}
  end

  test "rejects a command before the agent is ready" do
    state = %{handler_state("node-a") | socket: nil}
    job = %Job{id: "job-id", name: :container_start, parameters: ["container-id"]}

    assert {:reply, {:error, :client_not_ready}, ^state} =
             Handler.handle_call({:send_command, job}, self(), state)

    assert state.remote_jobs.entries == %{}
  end

  test "the server deadline exceeds the agent request budget and renews active or queued work" do
    alias Exdock.Protocol.ExecutionBudget
    assert ExecutionBudget.result_timeout() > ExecutionBudget.request_timeout()
    job = %Job{id: "job", name: :image_pull}
    state = handler_state("node-a") |> Handler.track_dispatched_job(job)
    assert Process.read_timer(state.remote_jobs.entries["job"].timer) > ExecutionBudget.request_timeout()
    old_token = state.remote_jobs.entries["job"].token

    for status <- ["queued", "running"] do
      assert {:ok, renewed} =
               HandlerState.renew_dispatched_job(state, WireMessage.progress("job", "image_pull", "node-a", status))

      assert {:error, :unknown_job} = Handler.expire_dispatched_job(renewed, "job", old_token)
      assert {:ok, accepted, ^job} = Handler.correlate_wire_result(renewed, wire_result("job", :image_pull, "node-a"))
      assert accepted.remote_jobs.entries == %{}
    end
  end

  test "activity cannot renew unknown, forged or mismatched jobs" do
    state = handler_state("node-a") |> Handler.track_dispatched_job(%Job{id: "job", name: :container_start})

    for {id, kind, node, reason} <- [
          {"other", "container_start", "node-a", :unknown_job},
          {"job", "image_delete", "node-a", :job_mismatch},
          {"job", "container_start", "node-b", :node_mismatch}
        ] do
      assert {:error, ^reason} = HandlerState.renew_dispatched_job(state, WireMessage.progress(id, kind, node, "running"))
    end

    Process.cancel_timer(state.remote_jobs.entries["job"].timer)
  end

  test "activity renewal preserves refresh generation" do
    state = handler_state("node-a") |> Handler.track_dispatched_job(%Job{id: "refresh", name: :node_refresh})
    generation = state.remote_jobs.entries["refresh"].job.refresh_generation

    assert {:ok, renewed} =
             HandlerState.renew_dispatched_job(state, WireMessage.progress("refresh", "node_refresh", "node-a", "running"))

    assert renewed.remote_jobs.entries["refresh"].job.refresh_generation == generation
    Process.cancel_timer(renewed.remote_jobs.entries["refresh"].timer)
  end

  test "an expired command closes the connection for reconciliation after agent work drains" do
    state = handler_state("node-a") |> Handler.track_dispatched_job(%Job{id: "expired", name: :container_stop})
    token = state.remote_jobs.entries["expired"].token
    assert {:stop, :client_job_timeout, updated} = Handler.handle_info({:remote_job_timeout, "expired", token}, state)
    assert updated.remote_jobs.entries == %{}
  end

  test "ignores stale timeout messages after a job id is retracked" do
    job = %Job{id: "job-id", name: :container_start}

    original_state =
      handler_state("node-a")
      |> Handler.track_dispatched_job(job)

    stale_token = original_state.remote_jobs.entries["job-id"].token
    current_state = Handler.track_dispatched_job(original_state, job)

    assert {:error, :unknown_job} =
             Handler.expire_dispatched_job(current_state, "job-id", stale_token)

    assert Map.has_key?(current_state.remote_jobs.entries, "job-id")
    Process.cancel_timer(current_state.remote_jobs.entries["job-id"].timer)
  end

  test "rejects forged job kinds without consuming the dispatched job" do
    state =
      handler_state("node-a")
      |> Handler.track_dispatched_job(%Job{id: "job-id", name: :container_start})

    forged_result = wire_result("job-id", :image_delete, "node-a")

    assert {:error, :job_mismatch} = Handler.correlate_wire_result(state, forged_result)

    assert {:ok, _state, %Job{}} =
             Handler.correlate_wire_result(state, wire_result("job-id", :container_start, "node-a"))
  end

  test "rejects results from unknown jobs or a different node" do
    state =
      handler_state("node-a")
      |> Handler.track_dispatched_job(%Job{id: "job-id", name: :container_start})

    assert {:error, :unknown_job} =
             Handler.correlate_wire_result(
               state,
               wire_result("unknown-job", :container_start, "node-a")
             )

    assert {:error, :node_mismatch} =
             Handler.correlate_wire_result(
               state,
               wire_result("job-id", :container_start, "node-b")
             )
  end

  defp wire_result(id, name, node) do
    {:ok, kind} = Command.external(name)
    WireMessage.result(id, kind, node, "result", nil)
  end

  defp handler_state(client_name),
    do: %HandlerState{session: authenticated_session(client_name), remote_jobs: RemoteJobs.new()}

  defp authenticated_session(client_name) do
    Session.new()
    |> Session.identify(client_name)
    |> Session.authenticate()
  end

  defp ready_session(client_name) do
    client_name
    |> authenticated_session()
    |> Session.offer_bundle("digest")
    |> Session.initialize()
  end
end
