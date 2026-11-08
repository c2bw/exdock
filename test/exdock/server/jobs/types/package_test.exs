defmodule Exdock.Server.Jobs.PackageTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Jobs

  test "new rejects invalid details before package work is queued" do
    assert_raise ArgumentError, "details must be a list of Jobs.Detail", fn ->
      Jobs.Package.new(:bulk_work, [detail(:ok), :invalid], nil)
    end
  end

  test "result ignores unrelated detail ids" do
    package = Jobs.Package.new(:bulk_work, [detail(:first)], nil)

    assert Jobs.Package.result(package, "missing", nil) == :detail_unknown
  end

  test "result keeps packages with remaining successful details" do
    first = detail(:first)
    second = detail(:second)
    package = Jobs.Package.new(:bulk_work, [first, second], nil)

    assert {:awaiting_more_results, %Jobs.Package{details: [^second]}} = Jobs.Package.result(package, first.id, nil)
  end

  test "preserves details so they can create individual log rows" do
    first = detail(:first)
    second = detail(:second)
    package = Jobs.Package.new(:bulk_work, [first, second], {2, ["first", "second"]})

    assert package.details == [first, second]
  end

  test "result finishes successfully on the final detail" do
    detail = detail(:only)
    package = Jobs.Package.new(:bulk_work, [detail], nil)

    assert Jobs.Package.result(package, detail.id, nil) == {:aggregate_complete, nil}
  end

  test "result fails fast when any detail reports an error" do
    first = detail(:first)
    second = detail(:second)
    package = Jobs.Package.new(:bulk_work, [first, second], nil)

    assert Jobs.Package.result(package, second.id, :failed) == {:aggregate_complete, :failed}
  end

  defp detail(name) do
    spec = Jobs.Spec.new(Jobs.Spec.Local.new(fn _id -> :ok end), [], nil)
    Jobs.Detail.new(name, spec)
  end
end
