defmodule Exdock.Server.Jobs.JobTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Jobs

  test "new turns a local spec into a local runtime job" do
    function = fn _id -> :ok end
    spec = Jobs.Spec.new(Jobs.Spec.Local.new(function), [:arg], %{source: :test})
    detail = Jobs.Detail.new(:local_work, spec)
    detail_id = detail.id

    assert %Jobs.Job{
             type: %Jobs.Job.Local{function: ^function},
             status: :none,
             id: ^detail_id,
             name: :local_work,
             parameters: [:arg],
             data: %{source: :test}
           } = Jobs.Job.new(detail, spec)
  end

  test "new turns a remote spec into a remote runtime job" do
    spec = Jobs.Spec.new(Jobs.Spec.Remote.new(["node_a", "node_b"]), ["container"], nil)
    detail = Jobs.Detail.new(:remote_work, spec)
    detail_id = detail.id

    assert %Jobs.Job{
             type: %Jobs.Job.Remote{nodes: ["node_a", "node_b"]},
             status: :none,
             id: ^detail_id,
             name: :remote_work,
             parameters: ["container"],
             data: nil
           } = Jobs.Job.new(detail, spec)
  end

  test "set_running leaves linked jobs linked" do
    job =
      :remote_work
      |> detail()
      |> job()
      |> Jobs.Job.set_linked()

    assert Jobs.Job.set_running(job) == job
  end

  defp detail(name) do
    Jobs.Detail.new(name, Jobs.Spec.new(Jobs.Spec.Local.new(fn _id -> :ok end), [], nil))
  end

  defp job(%Jobs.Detail{spec_list: [{spec, _id}]} = detail) do
    Jobs.Job.new(detail, spec)
  end
end
