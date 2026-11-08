defmodule ExdockWeb.LoginRateLimiterTest do
  use ExUnit.Case, async: true

  alias ExdockWeb.LoginRateLimiter

  test "limits attempts within a window and permits them after it expires" do
    clock = start_supervised!({Agent, fn -> 0 end})
    limiter = start_limiter(clock, max_attempts: 2, window_ms: 10_000)

    assert :ok = LoginRateLimiter.consume(:client, limiter)
    assert :ok = LoginRateLimiter.consume(:client, limiter)
    assert {:error, {:rate_limited, 10}} = LoginRateLimiter.consume(:client, limiter)

    Agent.update(clock, fn _now -> 10_000 end)

    assert :ok = LoginRateLimiter.consume(:client, limiter)
  end

  test "tracks sources independently and reset clears one source" do
    clock = start_supervised!({Agent, fn -> 0 end})
    limiter = start_limiter(clock, max_attempts: 1, window_ms: 10_000)

    assert :ok = LoginRateLimiter.consume(:first_client, limiter)
    assert {:error, {:rate_limited, 10}} = LoginRateLimiter.consume(:first_client, limiter)
    assert :ok = LoginRateLimiter.consume(:second_client, limiter)

    assert :ok = LoginRateLimiter.reset(:first_client, limiter)
    assert :ok = LoginRateLimiter.consume(:first_client, limiter)
  end

  defp start_limiter(clock, opts) do
    start_supervised!(
      {LoginRateLimiter,
       Keyword.merge(opts,
         name: nil,
         clock: fn -> Agent.get(clock, & &1) end
       )}
    )
  end
end
