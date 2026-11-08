# These tests are deliberately outside test/: ordinary mix test never requires
# Docker, and selecting this suite fails instead of silently skipping coverage.
for file <- ["harness.exs", "driver.exs"], do: Code.require_file(file, __DIR__)

unless System.argv() in [[], ["--release"]], do: raise("Usage: mix test.docker | mix test.release")
# Use the standalone client's existing HTTP dependencies and runtime settings.
# The server deliberately does not depend on the client's Hackney transport.
File.cd!(Path.expand("../..", __DIR__))
for app <- [:ex_docker_api, :hackney], do: Application.ensure_all_started(app) |> then(fn {:ok, _} -> :ok end)

export_directory = System.get_env("EXDOCK_TEST_RELEASE_EXPORT_DIR")
if export_directory && "--release" not in System.argv(), do: raise("Image export requires the production release suite")

ExUnit.start(autorun: false, timeout: 120_000, trace: true)
context = Exdock.DockerTest.Harness.start!()

try do
  context = Exdock.DockerTest.Harness.prepare!(context)
  release? = "--release" in System.argv()
  unless release?, do: ExUnit.configure(exclude: [mode: :release])
  context = if release?, do: Exdock.DockerTest.Driver.start_release!(context), else: context
  Application.put_env(:exdock, :docker_test_context, Map.put(context, :release?, release?))
  Application.put_env(:ex_docker_api, :base_url, context.endpoint)
  Application.put_env(:ex_docker_api, :timeout, 60_000)
  Application.put_env(:tesla, DockerEngineAPI.Connection, adapter: {Tesla.Adapter.Hackney, recv_timeout: 60_000})
  Code.require_file("commands_test.exs", __DIR__)
  result = ExUnit.run()

  if result.failures == 0 and export_directory,
    do: Exdock.DockerTest.Driver.export_release!(context, Path.expand(export_directory))

  if result.failures > 0, do: System.at_exit(fn _ -> exit({:shutdown, 1}) end)
after
  Exdock.DockerTest.Harness.diagnostics(context)
  Exdock.DockerTest.Harness.cleanup(context)
end
