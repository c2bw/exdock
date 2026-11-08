defmodule Exdock.Server.Jobs.Local.Registry.RequestBucketsTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Jobs.Local.Registry.RequestBuckets

  test "groups aliases of the same registry while preserving request order" do
    requests = [
      request("alpine:latest"),
      request("registry.example/team/api:latest"),
      request("docker.io/library/busybox:latest"),
      request("registry.example/team/worker:latest")
    ]

    assert %RequestBuckets{
             buckets: [
               [first, third],
               [second, fourth]
             ],
             max_concurrency: 2
           } = RequestBuckets.plan(requests)

    assert [first, second, third, fourth] == requests
  end

  test "keeps malformed references isolated from valid endpoints" do
    malformed = request("registry..example/team/app:latest")
    valid = request("registry.example/team/app:latest")

    assert %RequestBuckets{
             buckets: [[^malformed], [^valid]],
             max_concurrency: 2
           } = RequestBuckets.plan([malformed, valid])
  end

  test "uses one worker slot for an empty plan" do
    assert RequestBuckets.plan([]) == %RequestBuckets{buckets: [], max_concurrency: 1}
  end

  defp request(tag), do: %{tag: tag, platform: "linux/amd64"}
end
