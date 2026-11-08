defmodule Exdock.Server.Jobs.Local.Releases.HTTPRequestTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Jobs.Local.Releases.HTTPRequest

  test "request/2 passes the provider URL without auth when no token is configured" do
    request = request()
    releases_url = request.releases_url
    owner = self()

    transport = fn url, options ->
      send(owner, {:request, url, options})
      {:ok, %Req.Response{status: 200, body: []}}
    end

    assert {:ok, request.repo_url, []} == HTTPRequest.request(request, transport)
    assert_receive {:request, ^releases_url, []}
  end

  test "request/2 passes bearer authentication to the transport" do
    request = request(bearer_token: "secret-token")
    releases_url = request.releases_url
    owner = self()

    transport = fn url, options ->
      send(owner, {:request, url, options})
      {:ok, %Req.Response{status: 404}}
    end

    assert {:error, request.repo_url, :not_found} == HTTPRequest.request(request, transport)
    assert_receive {:request, ^releases_url, [auth: {:bearer, "secret-token"}]}
  end

  test "request/2 parses successful provider responses" do
    request = request()
    repo_url = request.repo_url

    transport = fn _url, _options ->
      {:ok,
       %Req.Response{
         status: 200,
         body: [
           %{
             "tag_name" => "v1.2.3",
             "html_url" => "https://github.com/openai/example/releases/tag/v1.2.3",
             "body" => "Release notes",
             "published_at" => "2026-01-02T03:04:05Z"
           }
         ]
       }}
    end

    assert {:ok, ^repo_url, [release]} = HTTPRequest.request(request, transport)
    assert release.source == :github
    assert release.version == "v1.2.3"
  end

  test "draft releases do not discard published releases in the same response" do
    published = %{
      "tag_name" => "v1",
      "html_url" => "https://github.com/openai/example/releases/tag/v1",
      "body" => "Published",
      "published_at" => "2026-01-02T03:04:05Z",
      "draft" => false
    }

    string_draft = %{published | "tag_name" => "v2", "published_at" => nil, "draft" => true}
    atom_draft = %{tag_name: "v3", published_at: nil, draft: true}
    transport = fn _url, _opts -> {:ok, %Req.Response{status: 200, body: [string_draft, published, atom_draft]}} end
    assert {:ok, _, [release]} = HTTPRequest.request(request(), transport)
    assert release.version == "v1"
    assert release.time_released == ~U[2026-01-02 03:04:05Z]
  end

  test "published releases without a timestamp use the fetch time" do
    fetched_at = ~U[2026-01-02 03:04:05Z]

    published = %{
      "tag_name" => "v1",
      "html_url" => "https://github.com/openai/example/releases/tag/v1",
      "body" => "Published",
      "published_at" => nil,
      "draft" => false
    }

    assert [release] = HTTPRequest.parse(request(), [published], fetched_at)
    assert release.time_released == fetched_at
  end

  test "request/2 normalizes rate limits across providers" do
    for status <- [403, 429] do
      transport = fn _url, _options -> {:ok, %Req.Response{status: status}} end

      assert {:error, "https://github.com/openai/example", :rate_limit} ==
               HTTPRequest.request(request(), transport)
    end
  end

  test "request/2 preserves transport failures" do
    error = %Req.TransportError{reason: :econnrefused}
    transport = fn _url, _options -> {:error, error} end

    assert {:error, "https://github.com/openai/example", ^error} =
             HTTPRequest.request(request(), transport)
  end

  test "request/2 reports unexpected response statuses" do
    transport = fn _url, _options -> {:ok, %Req.Response{status: 503}} end

    assert {:error, "https://github.com/openai/example", {:unexpected_status, 503}} ==
             HTTPRequest.request(request(), transport)
  end

  defp request(overrides \\ []) do
    struct!(
      %HTTPRequest{
        provider: :github,
        releases_url: "https://api.github.com/repos/openai/example/releases",
        bearer_token: nil,
        repo_name: "openai/example",
        repo_url: "https://github.com/openai/example"
      },
      overrides
    )
  end
end
