defmodule Exdock.Server.Logging.Status.JobRegistryTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Logging.Status
  alias Exdock.Server.Logging.Status.JobRegistry
  alias Exdock.Server.Jobs.Catalog

  @required_callbacks [
    data_init: 1,
    log: 1,
    add: 2,
    update: 2,
    result: 2,
    update_effects: 2,
    result_effects: 2,
    dash_key: 3,
    dash_data: 1,
    completion_log_options: 2
  ]

  test "status dashboard keys are derived from the canonical registrations" do
    registered_names = JobRegistry.names() |> MapSet.new()

    assert registered_names == MapSet.new(Catalog.names())
    assert JobRegistry.all() |> Map.keys() |> MapSet.new() == registered_names
    assert JobRegistry.initial_dash() |> Map.keys() |> MapSet.new() == registered_names
    assert Status.new().dash |> Map.keys() |> MapSet.new() == registered_names
    assert Enum.all?(JobRegistry.initial_dash(), fn {_job_name, entries} -> entries == %{} end)
  end

  test "every registration implements the status-job behaviour contract" do
    Enum.each(JobRegistry.all(), fn {job_name, registration} ->
      assert Code.ensure_loaded?(registration.module)

      Enum.each(@required_callbacks, fn {callback, arity} ->
        assert function_exported?(registration.module, callback, arity),
               "#{inspect(job_name)} is missing #{callback}/#{arity}"
      end)
    end)
  end

  test "job capabilities are read from the same registration" do
    mirrored_jobs =
      JobRegistry.all()
      |> Enum.filter(fn {_job_name, registration} -> registration.mirror_message? end)
      |> Enum.map(fn {job_name, _registration} -> job_name end)
      |> MapSet.new()

    assert mirrored_jobs ==
             MapSet.new([:container_recreate, :container_restart, :image_pull])

    assert JobRegistry.mirror_message?(:image_pull)
    refute JobRegistry.mirror_message?(:image_delete)
  end

  test "unknown jobs fail at the registry boundary" do
    assert_raise ArgumentError, "unknown status job: :unknown_job", fn ->
      JobRegistry.fetch!(:unknown_job)
    end
  end
end
