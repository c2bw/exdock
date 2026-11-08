defmodule Exdock.Server.Jobs.DetailTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Jobs

  test "new keeps a single spec on the parent detail id" do
    detail = Jobs.Detail.new(:single, sample_spec(), [])

    assert [{_, single_id}] = detail.spec_list
    assert single_id == detail.id
  end

  test "new generates sub ids for multi specs" do
    detail = Jobs.Detail.new(:multi, [sample_spec(), sample_spec()], [])

    assert [{_, first_id}, {_, second_id}] = detail.spec_list
    assert first_id != second_id
    assert String.starts_with?(first_id, "#{detail.id}.")
    assert String.starts_with?(second_id, "#{detail.id}.")
  end

  test "runnable? allows instant details only on instant events" do
    detail = Jobs.Detail.new(:instant, sample_spec(), [])

    assert Jobs.Detail.runnable?(detail, :instant)
    refute Jobs.Detail.runnable?(detail, {:finish, "other", nil})
  end

  test "runnable? enforces success requirements for failed upstream results" do
    upstream = Jobs.Detail.new(:upstream, sample_spec(), [])
    detail = Jobs.Detail.new(:chained_success, sample_spec(), trigger: {:finish, upstream.id}, requirements: :success)

    assert Jobs.Detail.runnable?(detail, {:finish, upstream.id, nil})
    refute Jobs.Detail.runnable?(detail, {:finish, upstream.id, :failed})
  end

  test "runnable? bypasses success requirements when requirements are :none" do
    upstream = Jobs.Detail.new(:upstream, sample_spec(), [])
    detail = Jobs.Detail.new(:chained_none, sample_spec(), trigger: {:finish, upstream.id}, requirements: :none)

    assert Jobs.Detail.runnable?(detail, {:finish, upstream.id, :failed})
  end

  test "chain_to rewrites the start trigger and requirements" do
    parent = Jobs.Detail.new(:parent, sample_spec(), [])
    child = Jobs.Detail.new(:child, sample_spec(), [])
    chained = Jobs.Detail.chain_to(child, parent)

    assert chained.start == {:finish, parent.id}
    assert chained.start_requirements == :success
  end

  test "remote spec normalizes a single node into a string node list" do
    assert Jobs.Spec.Remote.new("node_one").nodes == ["node_one"]
  end

  test "remote spec keeps an explicit node list unchanged" do
    nodes = ["node_one", "node_two"]
    assert Jobs.Spec.Remote.new(nodes).nodes == ["node_one", "node_two"]
  end

  test "remote spec rejects invalid node types" do
    assert_raise ArgumentError, "nodes must be strings", fn ->
      Jobs.Spec.Remote.new([:node_one, 2])
    end
  end

  defp sample_spec do
    Jobs.Spec.new(Jobs.Spec.Local.new(fn _id -> :ok end), [], nil)
  end
end
