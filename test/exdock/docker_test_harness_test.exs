defmodule Exdock.DockerTestHarnessTest do
  use ExUnit.Case, async: true

  @tag :tmp_dir
  test "daemon lookup uses its name when the first pull prints progress", %{tmp_dir: tmp_dir} do
    docker = Path.join(tmp_dir, "docker")

    File.write!(docker, """
    #!/bin/sh
    case "$1" in
      context) echo unix:///var/run/docker.sock ;;
      run)
        echo "Unable to find image locally; pulling layers" >&2
        echo fake-container-id
        ;;
      port)
        case "$2" in
          exdock-test-*) echo 127.0.0.1:12345 ;;
          *) echo "Invalid container lookup: $2" >&2; exit 1 ;;
        esac
        ;;
      --host) echo 29.8.1 ;;
      rm|logs) exit 0 ;;
      *) exit 1 ;;
    esac
    """)

    File.chmod!(docker, 0o755)
    harness = Path.expand("../../integration/docker/harness.exs", __DIR__)

    script = """
    Code.require_file(#{inspect(harness)})
    context = Exdock.DockerTest.Harness.start!()
    unless context.endpoint == "http://127.0.0.1:12345", do: raise("Wrong endpoint")
    IO.puts("Harness started successfully")
    """

    {output, status} =
      System.cmd(System.find_executable("elixir"), ["-e", script],
        cd: tmp_dir,
        env: [
          {"PATH", tmp_dir <> ":" <> System.get_env("PATH", "")},
          {"DOCKER_HOST", "unix:///var/run/docker.sock"},
          {"ERL_FLAGS", "+S 2:2"}
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "Harness started successfully"
  end

  @tag :tmp_dir
  test "readiness retries connection errors even when Docker reports success", %{tmp_dir: tmp_dir} do
    docker = Path.join(tmp_dir, "docker")

    File.write!(docker, """
    #!/bin/sh
    case "$1" in
      run) echo fake-container-id ;;
      port) echo 127.0.0.1:12345 ;;
      --host)
        case "$3" in
          info) echo "error during connect: connection reset by peer" ;;
          version)
            if [ "$4" = "--format" ]; then
              if [ ! -f first-probe ]; then
                touch first-probe
                echo "error during connect: connection reset by peer"
              elif [ ! -f second-probe ]; then
                touch second-probe
                echo "connection reset by peer" >&2
                exit 1
              else
                touch ready
                echo 29.8.1
              fi
            elif [ -f ready ]; then
              echo "Server: 29.8.1"
            else
              echo "Daemon not ready" >&2
              exit 1
            fi
            ;;
          *) exit 1 ;;
        esac
        ;;
      rm|logs) exit 0 ;;
      *) exit 1 ;;
    esac
    """)

    File.chmod!(docker, 0o755)
    harness = Path.expand("../../integration/docker/harness.exs", __DIR__)

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        ["-e", "Code.require_file(#{inspect(harness)}); Exdock.DockerTest.Harness.start!()"],
        cd: tmp_dir,
        env: [
          {"PATH", tmp_dir <> ":" <> System.get_env("PATH", "")},
          {"DOCKER_HOST", "unix:///var/run/docker.sock"},
          {"ERL_FLAGS", "+S 2:2"}
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert File.exists?(Path.join(tmp_dir, "first-probe"))
    assert File.exists?(Path.join(tmp_dir, "second-probe"))
    assert File.exists?(Path.join(tmp_dir, "ready"))
  end
end
