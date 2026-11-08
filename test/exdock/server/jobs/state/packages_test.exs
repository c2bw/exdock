defmodule Exdock.Server.Jobs.State.PackagesTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.State.Packages

  test "keeps packages with remaining successful details" do
    first = detail(:first)
    second = detail(:second)
    package = package([first, second])
    package_id = package.id

    {packages, []} =
      Packages.new()
      |> Packages.add(package)
      |> Packages.result(Jobs.Result.new(first.id, nil, nil))

    assert %Packages{packages: stored_packages} = packages
    assert %{^package_id => %Jobs.Package{details: [^second]}} = stored_packages
  end

  test "removes completed packages" do
    detail = detail(:only)
    package = package([detail])

    {packages, effects} =
      Packages.new()
      |> Packages.add(package)
      |> Packages.result(Jobs.Result.new(detail.id, nil, nil))

    assert packages == Packages.new()
    assert effects == [{:package_result, package.id, nil}]
  end

  test "removes failed packages" do
    first = detail(:first)
    second = detail(:second)
    package = package([first, second])

    {packages, effects} =
      Packages.new()
      |> Packages.add(package)
      |> Packages.result(Jobs.Result.new(second.id, nil, nil, :failed))

    assert packages == Packages.new()
    assert effects == [{:package_result, package.id, :failed}]
  end

  test "ignores unrelated detail results" do
    detail = detail(:only)
    package = package([detail])
    package_id = package.id

    {packages, []} =
      Packages.new()
      |> Packages.add(package)
      |> Packages.result(Jobs.Result.new("missing", nil, nil))

    assert %Packages{packages: stored_packages} = packages
    assert %{^package_id => ^package} = stored_packages
  end

  test "updates only the matching package on a terminal detail" do
    first = detail(:first)
    unrelated = detail(:unrelated)

    package_with_matching_detail = package([first])
    untouched_package = package([unrelated])
    untouched_package_id = untouched_package.id

    {packages, effects} =
      Packages.new()
      |> Packages.add(package_with_matching_detail)
      |> Packages.add(untouched_package)
      |> Packages.result(Jobs.Result.new(first.id, nil, nil))

    assert %Packages{packages: stored_packages} = packages
    refute Map.has_key?(stored_packages, package_with_matching_detail.id)
    assert %{^untouched_package_id => ^untouched_package} = stored_packages
    assert effects == [{:package_result, package_with_matching_detail.id, nil}]
  end

  test "completes every package waiting on the same terminal detail" do
    shared = detail(:shared)
    first_package = package([shared])
    second_package = package([shared])

    {packages, effects} =
      Packages.new()
      |> Packages.add(first_package)
      |> Packages.add(second_package)
      |> Packages.result(Jobs.Result.new(shared.id, nil, nil))

    assert packages == Packages.new()

    assert Enum.sort(effects) ==
             Enum.sort([
               {:package_result, first_package.id, nil},
               {:package_result, second_package.id, nil}
             ])
  end

  defp package(details), do: Jobs.Package.new(:bulk_work, details, nil)

  defp detail(name) do
    spec = Jobs.Spec.new(Jobs.Spec.Local.new(fn _id -> :ok end), [], nil)
    Jobs.Detail.new(name, spec)
  end
end
