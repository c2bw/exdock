defmodule Exdock.Server.Jobs.Local.Releases.ProviderTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Jobs.Local.Releases.Provider

  test "resolves supported providers from normalized repository URLs" do
    assert Provider.resolve("  https://github.com/openai/example/  ") ==
             {:ok, :github, "openai/example"}

    assert Provider.resolve("gitlab.com/group/subgroup/example") ==
             {:ok, :gitlab, "group/subgroup/example"}
  end

  test "rejects unsupported hosts and empty repository paths" do
    assert Provider.resolve("https://example.com/openai/example") == :unsupported
    assert Provider.resolve("https://github.com/") == :unsupported
  end

  test "builds provider-specific release API URLs" do
    assert Provider.releases_url(:github, "openai/example") ==
             "https://api.github.com/repos/openai/example/releases"

    assert Provider.releases_url(:gitlab, "group/subgroup/example") ==
             "https://gitlab.com/api/v4/projects/group%2Fsubgroup%2Fexample/releases"
  end
end
