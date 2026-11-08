defmodule Exdock.Server.Jobs.Local.Registry.FetcherTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.Local.Registry.{Context, Fetcher, FetchReport}
  alias Exdock.Server.State.Storage.TagsInfo
  alias Exdock.Domain.TagInfo

  test "fetch/4 resolves metadata and publishes progress through its context" do
    owner = self()
    image_tag = "registry.example/team/app:latest"
    platform = "linux/amd64"
    job_id = "registry-job"
    previous_date = ~U[2026-01-02 03:04:05Z]
    remote_date = ~U[2026-02-03 04:05:06Z]
    check_date = ~U[2026-03-04 05:06:07Z]

    previous = TagInfo.new(image_tag, platform, "sha256:old", previous_date, previous_date)
    tags_info = %TagsInfo{tags: %{{image_tag, platform} => previous}}

    context =
      Context.new(
        metadata_lookup: fn ^image_tag, ^platform, ^previous ->
          send(owner, :metadata_looked_up)
          {"sha256:new", remote_date}
        end,
        clock: fn -> check_date end,
        update_publisher: &send(owner, {:registry_update, &1}),
        max_concurrency: 1
      )

    assert {:ok,
            %FetchReport{
              tags: [
                %TagInfo{
                  tag: ^image_tag,
                  platform: ^platform,
                  latest_digest: "sha256:new",
                  latest_date: ^remote_date,
                  check_date: ^check_date
                }
              ],
              request_failures: [],
              worker_exits: []
            }} = Fetcher.fetch([%{tag: image_tag, platform: platform}], tags_info, job_id, context)

    assert_receive :metadata_looked_up

    assert_receive {:registry_update,
                    %Jobs.Update{
                      id: ^job_id,
                      update: ^image_tag,
                      remove_node: false,
                      error: nil
                    }}
  end

  test "fetch/4 turns lookup failures into deterministic tag metadata and error updates" do
    owner = self()
    image_tag = "registry.example/team/missing:latest"
    platform = "linux/arm64"
    check_date = ~U[2026-04-05 06:07:08Z]

    context =
      Context.new(
        metadata_lookup: fn ^image_tag, ^platform, nil ->
          raise "registry unavailable"
        end,
        clock: fn -> check_date end,
        update_publisher: &send(owner, {:registry_update, &1}),
        max_concurrency: 1
      )

    assert {:ok,
            %FetchReport{
              tags: [
                %TagInfo{
                  tag: ^image_tag,
                  platform: ^platform,
                  latest_digest: "",
                  latest_date: ~U[1970-01-01 00:00:00Z],
                  check_date: ^check_date
                }
              ],
              request_failures: [
                %{tag: ^image_tag, platform: ^platform, reason: %RuntimeError{message: "registry unavailable"}}
              ],
              worker_exits: []
            }} =
             Fetcher.fetch(
               [%{tag: image_tag, platform: platform}],
               %TagsInfo{tags: %{}},
               "registry-job",
               context
             )

    assert_receive {:registry_update,
                    %Jobs.Update{
                      update: ^image_tag,
                      error: %RuntimeError{message: "registry unavailable"}
                    }}
  end

  test "context rejects invalid collaborators before execution" do
    assert_raise ArgumentError, "invalid registry fetch context", fn ->
      Context.new(clock: :not_a_function)
    end
  end
end
