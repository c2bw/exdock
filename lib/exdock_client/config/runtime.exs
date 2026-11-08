import Config

auth_key =
  if config_env() == :prod do
    case System.get_env("AUTH_KEY") do
      value when is_binary(value) and value != "" -> value
      _ -> raise "environment variable AUTH_KEY is missing or empty"
    end
  else
    System.get_env("AUTH_KEY") || "example"
  end

config :exdock_client, :node_name, System.get_env("NODE_NAME", "example_name")
config :exdock_client, :server_host, System.get_env("SERVER_HOST") || "localhost"
config :exdock_client, :server_port, System.get_env("SERVER_PORT", "5000") |> String.to_integer(10)
config :exdock_client, :auth_key, auth_key

readiness_timeout = System.get_env("RECREATE_READINESS_TIMEOUT_MS", "30000") |> String.to_integer()
if readiness_timeout < 0, do: raise("RECREATE_READINESS_TIMEOUT_MS must be non-negative")

config :exdock_client, :recreation_readiness,
  readiness: readiness_timeout > 0,
  readiness_timeout: readiness_timeout

request_timeout = Exdock.Protocol.ExecutionBudget.request_timeout()
config :tesla, DockerEngineAPI.Connection, adapter: {Tesla.Adapter.Hackney, recv_timeout: request_timeout}
config :ex_docker_api, base_url: "http+unix://%2Fvar%2Frun%2Fdocker.sock/", timeout: request_timeout
