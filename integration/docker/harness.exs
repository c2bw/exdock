defmodule Exdock.DockerTest.Harness do
  @moduledoc false
  @label "exdock.test.run"

  def start! do
    for executable <- ["docker", "timeout"] do
      unless System.find_executable(executable), do: raise("#{executable} is required")
    end

    # The published nested-daemon port is only reachable on a local Docker host.
    host = System.get_env("DOCKER_HOST") || host!(["context", "inspect", "--format", "{{.Endpoints.docker.Host}}"])
    unless String.starts_with?(host, "unix://"), do: raise("Run on a local Unix-socket Docker host (received #{host})")
    id = "exdock-test-" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
    artifacts = Path.expand(".docker-test-artifacts/#{id}")
    File.mkdir_p!(artifacts)
    image = System.get_env("EXDOCK_TEST_DIND_IMAGE", "docker:29.8.1-dind")
    IO.puts("Starting isolated Docker Engine: #{image}\nArtifacts: #{artifacts}")

    # Use the unique name for cleanup even if Docker creates the container but
    # fails before run returns successfully (for example, missing privileges).
    context = %{id: id, daemon: id, artifacts: artifacts}
    System.at_exit(fn _ -> cleanup(context) end)

    # Docker may print image-pull progress alongside the ID on first use.
    # Address the container by its assigned name, not the merged command output.
    host!(
      [
        "run",
        "-d",
        "--privileged",
        "--name",
        id,
        "--label",
        "#{@label}=#{id}",
        "-e",
        "DOCKER_TLS_CERTDIR=",
        "-p",
        "127.0.0.1::2375",
        image,
        "--host=tcp://0.0.0.0:2375",
        "--host=unix:///var/run/docker.sock",
        "--insecure-registry=127.0.0.1:5001"
      ],
      180
    )

    try do
      mapping = host!(["port", context.daemon, "2375/tcp"])
      [_, port] = String.split(mapping, ":")
      context = Map.put(context, :endpoint, "http://127.0.0.1:#{port}")

      eventually!(
        fn ->
          case docker(context, ["info", "--format", "{{.ServerVersion}}"], 5) do
            {version, 0} -> {:ok, version}
            _ -> false
          end
        end,
        "nested Docker daemon readiness",
        60_000
      )

      File.write!(Path.join(artifacts, "engine.txt"), docker!(context, ["version"]))
      context
    rescue
      error ->
        diagnostics(context)
        cleanup(context)
        reraise error, __STACKTRACE__
    end
  end

  def cleanup(context) do
    # Never prune or enumerate/delete resources on the parent host.
    # Removing this one daemon and its anonymous volumes removes all fixtures.
    host(["rm", "-fv", context.daemon], 30)
    :ok
  end

  def diagnostics(context) do
    {logs, _} = host(["logs", context.daemon], 15)
    File.write!(Path.join(context.artifacts, "daemon.log"), logs)

    if Map.has_key?(context, :endpoint) do
      {containers, _} = docker(context, ["ps", "-a", "--no-trunc"], 10)
      File.write!(Path.join(context.artifacts, "containers.txt"), containers)

      for name <- ["suite-server", "suite-agent", "suite-registry"] do
        {logs, _} = docker(context, ["logs", name], 10)
        File.write!(Path.join(context.artifacts, "#{name}.log"), logs)
      end
    end
  end

  def docker(context, args, timeout \\ 60) do
    endpoint = String.replace_prefix(context.endpoint, "http://", "tcp://")

    result =
      command(["--host", endpoint | args], timeout, [
        {"DOCKER_CONTEXT", nil},
        {"DOCKER_TLS_VERIFY", nil},
        {"DOCKER_CERT_PATH", nil}
      ])

    {output, status} = result
    File.write!(Path.join(context.artifacts, "commands.log"), "#{inspect(args)} => #{status}\n#{output}\n", [:append])
    result
  end

  def docker!(context, args, timeout \\ 60) do
    case docker(context, args, timeout) do
      {output, 0} -> String.trim(output)
      {output, status} -> raise "Docker command failed (#{status}): #{inspect(args)}\n#{output}"
    end
  end

  # Retry infrastructure downloads/builds, never the commands under test.
  def setup_command!(context, args, timeout, attempts \\ 3) do
    case docker(context, args, timeout) do
      {output, 0} ->
        String.trim(output)

      {_, _} when attempts > 1 ->
        IO.puts("Retrying fixture/build setup: #{inspect(Enum.take(args, 3))}")
        setup_command!(context, args, timeout, attempts - 1)

      {output, status} ->
        raise "Docker setup failed (#{status}): #{inspect(args)}\n#{output}"
    end
  end

  def host(args, timeout \\ 60), do: command(args, timeout, [])

  def host!(args, timeout \\ 60) do
    case host(args, timeout) do
      {output, 0} -> String.trim(output)
      {output, status} -> raise "Parent Docker command failed (#{status}): #{inspect(args)}\n#{output}"
    end
  end

  defp command(args, timeout, env) do
    System.cmd("timeout", ["--signal=TERM", "--kill-after=10s", "#{timeout}s", "docker" | args], stderr_to_stdout: true, env: env)
  end

  def eventually!(fun, description, timeout \\ 20_000) do
    poll(fun, description, System.monotonic_time(:millisecond) + timeout)
  end

  defp poll(fun, description, deadline) do
    case fun.() do
      {:ok, value} ->
        value

      value when value in [false, nil] ->
        if System.monotonic_time(:millisecond) >= deadline do
          raise "Timed out waiting for #{description}"
        end

        # Docker readiness is external state; poll it with a bounded deadline.
        receive do
        after
          100 -> poll(fun, description, deadline)
        end
    end
  end

  def inspect!(context, name) do
    [value] = context |> docker!(["inspect", name]) |> JSON.decode!()
    value
  end

  def prepare!(context) do
    docker!(context, ["network", "create", "suite-net"])
    registry_image = System.get_env("EXDOCK_TEST_REGISTRY_IMAGE", "registry:3.0.0")
    setup_command!(context, ["pull", registry_image], 180)
    setup_command!(context, ["pull", System.get_env("EXDOCK_TEST_BASE_IMAGE", "alpine:3.24")], 180)

    docker!(
      context,
      [
        "run",
        "-d",
        "--name",
        "suite-registry",
        "--network",
        "suite-net",
        "--label",
        "exdock.protected=true",
        "-p",
        "127.0.0.1:5001:5000",
        registry_image
      ],
      180
    )

    directory = Path.join(context.artifacts, "fixture")
    File.mkdir_p!(directory)

    File.write!(Path.join(directory, "Dockerfile"), """
    FROM #{System.get_env("EXDOCK_TEST_BASE_IMAGE", "alpine:3.24")}
    ARG VERSION
    RUN apk add --no-cache busybox-extras && mkdir -p /www /data && printf '%s' "$VERSION" > /www/index.html
    ENV FIXTURE_SETTING=preserved
    LABEL exdock.test.fixture=true
    EXPOSE 8080
    VOLUME ["/data"]
    HEALTHCHECK --interval=1s --timeout=1s --retries=10 CMD wget -q -O - http://127.0.0.1:8080/ || exit 1
    CMD ["httpd", "-f", "-p", "8080", "-h", "/www"]
    """)

    for version <- ["a", "b"] do
      setup_command!(context, ["build", "--build-arg", "VERSION=#{version}", "-t", "fixture:#{version}", directory], 300)
    end

    # This image deliberately lacks the original command (httpd), so Docker
    # accepts create but rejects start. Rollback must restore the real original.
    File.write!(Path.join(directory, "Dockerfile.broken"), "FROM #{System.get_env("EXDOCK_TEST_BASE_IMAGE", "alpine:3.24")}\n")
    setup_command!(context, ["build", "-f", Path.join(directory, "Dockerfile.broken"), "-t", "fixture:broken", directory], 300)

    File.write!(Path.join(directory, "Dockerfile.unhealthy"), "FROM fixture:b\nRUN rm /www/index.html\n")

    setup_command!(
      context,
      ["build", "-f", Path.join(directory, "Dockerfile.unhealthy"), "-t", "fixture:unhealthy", directory],
      300
    )

    File.write!(Path.join(directory, "Dockerfile.exits"), """
    FROM fixture:b
    RUN printf '#!/bin/sh\\nexit 42\\n' > /usr/local/bin/httpd && chmod +x /usr/local/bin/httpd
    """)

    setup_command!(context, ["build", "-f", Path.join(directory, "Dockerfile.exits"), "-t", "fixture:exits", directory], 300)

    publish!(context, "a")
    context
  end

  def tag, do: "127.0.0.1:5001/exdock-fixture:rolling"

  def publish!(context, version) do
    docker!(context, ["tag", "fixture:#{version}", tag()])
    docker!(context, ["push", tag()])
  end

  def create!(context, opts \\ []) do
    publish!(context, "a")
    name = "fixture-" <> Base.encode16(:crypto.strong_rand_bytes(5), case: :lower)

    mounts =
      case Keyword.get(opts, :volume, :anonymous) do
        :anonymous -> []
        :named -> ["-v", "#{name}-data:/data"]
        :prefix -> ["-v", "/data", "-v", "#{name}-data:/data2", "-v", "/data:/backup"]
      end

    networking =
      case Keyword.get(opts, :network, :bridge) do
        :bridge -> ["--network", "suite-net", "--network-alias", name, "-p", "127.0.0.1::8080"]
        :host -> ["--network", "host"]
      end

    image = Keyword.get(opts, :image, tag())
    health = if Keyword.get(opts, :healthcheck, true), do: [], else: ["--no-healthcheck"]
    removal = if Keyword.get(opts, :auto_remove, false), do: ["--rm"], else: []
    stop = ["--stop-timeout", to_string(Keyword.get(opts, :stop_timeout, 1))]

    docker!(
      context,
      ["run", "-d", "--name", name, "--label", "#{@label}=#{context.id}"] ++
        networking ++ mounts ++ health ++ removal ++ stop ++ [image]
    )

    ready!(context, name, "a")
    docker!(context, ["exec", name, "sh", "-c", "printf preserved > /data/sentinel"])
    name
  end

  def ready!(context, name, version) do
    eventually!(
      fn ->
        case docker(context, ["exec", name, "wget", "-q", "-O", "-", "http://127.0.0.1:8080/"], 5) do
          {body, 0} when body == version -> {:ok, true}
          _ -> false
        end
      end,
      "#{name} serving version #{version}"
    )
  end

  def remove!(context, name) do
    docker(context, ["rm", "-fv", name])
    docker(context, ["volume", "rm", "#{name}-data"])
  end
end
