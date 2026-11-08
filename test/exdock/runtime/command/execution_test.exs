defmodule Exdock.Runtime.Command.ExecutionTest do
  use ExUnit.Case, async: true

  alias Exdock.Runtime.Command.Execution
  alias Exdock.Server.Jobs.{Detail, Plan, Spec}
  alias Exdock.Server.State

  test "finishes empty plans as no-ops" do
    state = %State{}
    operation_id = Ecto.UUID.generate()

    assert {^state, [{:finish_operation, ^operation_id, :refresh_cluster, %{status: :noop}}]} =
             Execution.resolve(
               state,
               {:work, Plan.new(nil)},
               operation_id,
               :refresh_cluster,
               []
             )
  end

  test "prepares non-empty plans for submission" do
    state = %State{}
    operation_id = Ecto.UUID.generate()
    detail = Detail.new(:example, Spec.new(Spec.Local.new(fn _job_id -> :ok end), [], nil))

    assert {^state, [{:submit_plan, %Plan{} = plan}]} =
             Execution.resolve(
               state,
               {:work, Plan.new(detail)},
               operation_id,
               :example,
               automated: true
             )

    assert plan.operation_id == operation_id
    assert plan.automated?
  end

  test "publishes completed state outcomes" do
    state = %State{}
    updated_state = %{state | revision: 1}
    operation_id = Ecto.UUID.generate()

    assert {^updated_state, [{:finish_operation, ^operation_id, :state_change, %{status: :completed}}]} =
             Execution.resolve(
               state,
               {:state, updated_state},
               operation_id,
               :state_change,
               []
             )
  end

  test "publishes a state outcome's structured operation result" do
    state = %State{}
    updated_state = %{state | revision: 1}
    operation_id = Ecto.UUID.generate()
    result = %{status: :completed, import_report: %{skipped: 2}}

    assert {^updated_state, [{:finish_operation, ^operation_id, :state_change, ^result}]} =
             Execution.resolve(
               state,
               {:state, updated_state, result},
               operation_id,
               :state_change,
               []
             )
  end

  test "retains state and publishes command failures" do
    state = %State{}
    operation_id = Ecto.UUID.generate()

    assert {^state, [{:finish_operation, ^operation_id, :example, %{error: :rejected}}]} =
             Execution.resolve(state, {:error, :rejected}, operation_id, :example, [])
  end

  test "omits completion effects for internal commands" do
    state = %State{}

    assert {^state, []} =
             Execution.resolve(state, {:error, :rejected}, nil, :state_change, [])
  end
end
