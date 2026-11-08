defmodule Exdock.Server.Jobs.Local.Releases.FetcherTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.Local.Releases.{Context, Fetcher, HTTPRequest}

  test "fetch/3 executes requests and publishes progress through its context" do
    owner = self()
    github = request(:github, "openai/example")
    gitlab = request(:gitlab, "group/example")
    github_url = github.repo_url
    gitlab_url = gitlab.repo_url

    context =
      Context.new(
        request_executor: fn request ->
          send(owner, {:executed, request.repo_url})
          {:ok, request.repo_url, []}
        end,
        update_publisher: &send(owner, {:release_update, &1}),
        max_concurrency: 2,
        timeout: :infinity
      )

    assert {:ok, results} = Fetcher.fetch([github, gitlab], "release-job", context)

    assert MapSet.new(results) ==
             MapSet.new([
               {:ok, github.repo_url, []},
               {:ok, gitlab.repo_url, []}
             ])

    assert_receive {:executed, ^github_url}
    assert_receive {:executed, ^gitlab_url}

    assert_receive {:release_update,
                    %Jobs.Update{
                      id: "release-job",
                      update: {:github, "openai/example"},
                      remove_node: false,
                      error: nil
                    }}

    assert_receive {:release_update,
                    %Jobs.Update{
                      id: "release-job",
                      update: {:gitlab, "group/example"},
                      remove_node: false,
                      error: nil
                    }}
  end

  test "fetch/3 publishes progress for normalized request errors" do
    owner = self()
    request = request(:github, "openai/missing")

    context =
      Context.new(
        request_executor: fn request -> {:error, request.repo_url, :not_found} end,
        update_publisher: &send(owner, {:release_update, &1}),
        max_concurrency: 1,
        timeout: :infinity
      )

    assert {:ok, [{:error, request.repo_url, :not_found}]} ==
             Fetcher.fetch([request], "release-job", context)

    assert_receive {:release_update, %Jobs.Update{update: {:github, "openai/missing"}}}
  end

  test "fetch/3 reports request task exits without publishing false progress" do
    context =
      Context.new(
        request_executor: fn _request -> exit(:normal) end,
        update_publisher: &send(self(), {:release_update, &1}),
        max_concurrency: 1,
        timeout: :infinity
      )

    assert {:error, {:task_exit, _reason}} =
             Fetcher.fetch([request(:github, "openai/example")], "release-job", context)

    refute_receive {:release_update, _update}
  end

  test "fetch/3 reports request timeouts" do
    context =
      Context.new(
        request_executor: fn _request ->
          receive do
            :continue -> {:error, "unused", :unexpected}
          end
        end,
        update_publisher: &send(self(), {:release_update, &1}),
        max_concurrency: 1,
        timeout: 10
      )

    assert {:error, :timeout} =
             Fetcher.fetch([request(:github, "openai/example")], "release-job", context)

    refute_receive {:release_update, _update}
  end

  test "summarize/1 separates errors and flattens successful releases" do
    releases = [:first_release, :second_release]
    error = {:error, "https://gitlab.com/group/missing", :not_found}

    assert %{errors: [^error], releases: ^releases} =
             Fetcher.summarize([
               {:ok, "https://github.com/openai/example", releases},
               error
             ])
  end

  test "context rejects invalid collaborators and stream limits" do
    assert_raise ArgumentError, "invalid release fetch context", fn ->
      Context.new(request_executor: :not_a_function)
    end

    assert_raise ArgumentError, "invalid release fetch context", fn ->
      Context.new(max_concurrency: 0)
    end

    assert_raise ArgumentError, "invalid release fetch context", fn ->
      Context.new(timeout: 0)
    end
  end

  defp request(provider, repo_name) do
    host = if provider == :github, do: "github.com", else: "gitlab.com"

    %HTTPRequest{
      provider: provider,
      releases_url: "https://#{host}/api/releases/#{repo_name}",
      bearer_token: nil,
      repo_name: repo_name,
      repo_url: "https://#{host}/#{repo_name}"
    }
  end
end
