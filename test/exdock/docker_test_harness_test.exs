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
      --host) echo fake-engine-version ;;
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
end
