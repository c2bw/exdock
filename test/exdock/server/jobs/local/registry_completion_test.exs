defmodule Exdock.Server.Jobs.Local.RegistryCompletionTest do
  use Exdock.DataCase, async: false

  alias Exdock.Domain.TagInfo
  alias Exdock.Runtime.Command.Workflow
  alias Exdock.Server
  alias Exdock.Server.Jobs
  alias Jobs.Local.Registry
  alias Registry.FetchReport
  alias Exdock.Server.State.Storage
  alias Storage.Persistence.TagInfo, as: TagPersistence

  setup do
    coordinator = start_supervised!({Server, email: "registry@example.com", plain_password: "test-password-123"})
    %{runtime: Jobs.Runtime.new(jobs: self(), coordinator: coordinator), coordinator: coordinator}
  end

  test "an entirely failed fetch publishes a terminal error", %{runtime: runtime} do
    container = %Exdock.Domain.Container{
      node: "node",
      name: "app",
      id: "app-id",
      core: %Exdock.Domain.Container.Core{
        is_running: true,
        image_data: %Exdock.Domain.Container.Core.ImageData{
          tag_info: %TagInfo{tag: "registry..example/app:latest"}
        }
      }
    }

    detail = Registry.build_detail([container], %Storage.TagsInfo{tags: %{}}, %{"node" => "linux/amd64"})
    [{spec, _}] = detail.spec_list
    job_id = detail.id
    ExUnit.CaptureLog.capture_log(fn -> spec.location.function.(job_id, runtime) end)
    assert_receive {:"$gen_cast", {:job_update, %Jobs.Update{error: error}}}
    assert error != nil
    assert_receive {:"$gen_cast", {:job_result, %Jobs.Result{id: ^job_id, error: {:registry_fetch_failed, failures}} = result}}
    assert [%{tag: "registry..example/app:latest"}] = failures.request_failures
    assert failures.worker_exits == []
    assert_stopped(Jobs.Detail.set_continuation(detail, Workflow.new(:containers_update, [])), result)
  end

  test "partial fetches persist metadata before stopping the continuation", %{runtime: runtime, coordinator: coordinator} do
    tag = tag_info()
    failure = %{tag: "missing:latest", platform: "linux/amd64", reason: :unavailable}
    report = %FetchReport{tags: [tag], request_failures: [failure]}
    detail = local_detail()
    ExUnit.CaptureLog.capture_log(fn -> Registry.complete_refresh({:ok, report}, detail.id, runtime) end)
    assert_receive {:"$gen_cast", {:job_result, %Jobs.Result{} = result}}
    assert result.error == {:registry_fetch_failed, %{request_failures: [failure], worker_exits: []}}
    assert Storage.TagsInfo.get(:sys.get_state(coordinator).tags, tag.tag, tag.platform) == tag
    assert Enum.any?(TagPersistence.load_all(), &(&1 == tag))
    assert_stopped(detail, result)
  end

  test "worker exits stop the workflow even with no request failures", %{runtime: runtime} do
    detail = local_detail()
    report = %FetchReport{worker_exits: [{:task_exit, :killed}]}
    ExUnit.CaptureLog.capture_log(fn -> Registry.complete_refresh({:ok, report}, detail.id, runtime) end)
    assert_receive {:"$gen_cast", {:job_result, %Jobs.Result{} = result}}
    assert result.error == {:registry_fetch_failed, %{request_failures: [], worker_exits: [{:task_exit, :killed}]}}
    assert_stopped(detail, result)
  end

  test "a complete fetch persists tags and releases its continuation", %{runtime: runtime, coordinator: coordinator} do
    tag = tag_info()
    detail = local_detail()
    Registry.complete_refresh({:ok, %FetchReport{tags: [tag]}}, detail.id, runtime)
    assert_receive {:"$gen_cast", {:job_result, %Jobs.Result{error: nil} = result}}
    assert Storage.TagsInfo.get(:sys.get_state(coordinator).tags, tag.tag, tag.platform) == tag
    {state, _} = Jobs.State.transition(Jobs.State.new(), {:add, detail})
    {_, effects} = Jobs.State.transition(state, {:result, result})
    assert {:server_command, detail.continuation} in effects
  end

  test "persistence failure leaves tags unchanged and stops the workflow", %{runtime: runtime, coordinator: coordinator} do
    tag = tag_info()
    invalid = %{tag | tag: ""}
    detail = local_detail()
    before = :sys.get_state(coordinator).tags
    report = %FetchReport{tags: [tag, invalid], worker_exits: [:timeout]}

    ExUnit.CaptureLog.capture_log(fn -> Registry.complete_refresh({:ok, report}, detail.id, runtime) end)
    assert_receive {:"$gen_cast", {:job_result, %Jobs.Result{error: {:state_change_failed, _}} = result}}
    assert :sys.get_state(coordinator).tags == before
    assert TagPersistence.load(tag.tag, tag.platform) == nil
    assert_stopped(detail, result)
  end

  defp local_detail do
    Jobs.Detail.new(:registry_fetch, Jobs.Spec.new(Jobs.Spec.Local.new(fn _ -> :ok end), [], nil),
      continuation: Workflow.new(:containers_update, [])
    )
  end

  defp assert_stopped(detail, result) do
    {state, _} = Jobs.State.transition(Jobs.State.new(), {:add, detail})
    {state, effects} = Jobs.State.transition(state, {:result, result})
    assert {:workflow_stopped, result.error} in effects
    refute Enum.any?(effects, &match?({:server_command, _}, &1))
    assert Jobs.State.get_job_info(state, detail.id) == nil
    assert Jobs.State.invariant_errors(state) == []
  end

  defp tag_info do
    TagInfo.new("app:latest", "linux/amd64", "sha256:remote", ~U[2026-01-01 00:00:00Z], ~U[2026-11-07 12:00:00Z])
  end
end
