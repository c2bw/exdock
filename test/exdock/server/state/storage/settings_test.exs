defmodule Exdock.Server.State.Storage.SettingsTest do
  use Exdock.DataCase, async: false

  import ExUnit.CaptureLog

  alias Exdock.Configuration
  alias Exdock.Server.State
  alias Exdock.Server.State.Domains.Settings, as: SettingsDomain
  alias Exdock.Runtime.Mutation
  alias Exdock.Runtime.MutationContract
  alias Exdock.Server.State.Storage.Persistence.ContainerSettings, as: ContainerSettingsPersistence
  alias Exdock.Server.State.Storage.Persistence.ImageMetadata
  alias Exdock.Server.State.Storage.Persistence.ImageSettings, as: ImageSettingsPersistence
  alias Exdock.Server.State.Storage.Persistence.Node, as: NodePersistence
  alias Exdock.Server.State.Storage.Persistence.UserSettings, as: UserSettingsPersistence
  alias Exdock.Server.State.Storage.Settings
  alias Exdock.Server.State.Storage.Settings.Importer.Report
  alias Exdock.Domain.Image.Metadata
  alias Exdock.Domain.Image.Settings, as: ImageSettings
  alias Exdock.Domain.Container.Settings, as: ContainerSettings
  alias Exdock.Domain.Node
  alias Exdock.Domain.UserSettings
  alias Exdock.Server.State.PeriodicJob
  alias Exdock.Server.State.Change.{Outcome, Plan}

  test "rejects an impossible cron before persistence and filters it on import" do
    user = UserSettings.default_user()
    existing = UserSettings.default() |> UserSettings.set(:cron_string, "0 8 * * *")
    assert {:ok, _record} = UserSettingsPersistence.insert(existing)
    settings = Settings.load()

    assert {:error, {:invalid_user_setting_value, :cron_string}} =
             Settings.change_user_setting(settings, :cron_string, "0 0 31 2 *")

    assert UserSettingsPersistence.load(user).cron_string == "0 8 * * *"

    configuration = %Configuration{user_settings: %{"cron_string" => "0 0 31 2 *"}}
    assert {:ok, _settings, %Report{}} = Settings.import(configuration)
    assert UserSettingsPersistence.load(user).cron_string == UserSettings.default().cron_string
  end

  test "change/2 persists user setting updates and forces a broadcast" do
    user = UserSettings.default_user()
    state = %State{settings: %Settings{user: %{user => UserSettings.default()}}}
    assert {:ok, payload} = Mutation.user_setting(:cron_string, "0 8 * * *")

    assert %Outcome{
             state: %State{settings: settings},
             broadcast_opts: [delayed: false, force: true],
             effects: []
           } =
             execute_plan(SettingsDomain, state, payload)

    assert %UserSettings{cron_string: "0 8 * * *"} = Settings.get(settings)
    assert %UserSettings{cron_string: "0 8 * * *"} = UserSettingsPersistence.load(user)
  end

  test "change/2 imports typed configuration and reloads user settings from storage" do
    user = UserSettings.default_user()

    configuration = %Configuration{
      user_settings: %{
        "automation_enabled" => true,
        "auto_update_above" => 4,
        "cron_string" => "0 6 * * *"
      }
    }

    state = %State{settings: %Settings{user: %{user => UserSettings.default()}}}
    payload = %Mutation{domain: :settings, action: :import, data: configuration}

    assert %Outcome{
             state: %State{settings: settings},
             broadcast_opts: [delayed: false, force: true],
             effects: [],
             operation_result: %{
               status: :completed,
               import_report: %Report{applied: %{user_settings: 3}, skipped: 0}
             }
           } =
             execute_plan(SettingsDomain, state, payload)

    assert %UserSettings{
             automation_enabled: true,
             auto_update_above: 4,
             cron_string: "0 6 * * *"
           } = Settings.get(settings)
  end

  test "change/2 reschedules the periodic job when an import changes cron" do
    user = UserSettings.default_user()
    periodic_job = PeriodicJob.create("0 22 * * *")

    configuration = %Configuration{user_settings: %{"cron_string" => "0 6 * * *"}}

    state = %State{
      settings: %Settings{user: %{user => UserSettings.default()}},
      periodic_job: periodic_job
    }

    payload = %Mutation{domain: :settings, action: :import, data: configuration}

    assert %Outcome{
             state: %State{periodic_job: updated_job},
             broadcast_opts: [delayed: false, force: true],
             effects: [],
             operation_result: %{status: :completed, import_report: %Report{skipped: 0}}
           } =
             execute_plan(SettingsDomain, state, payload)

    assert %PeriodicJob{cron_string: "0 6 * * *"} = updated_job
    refute updated_job.next_run == periodic_job.next_run
  end

  test "change/2 imports only settings for known runtime nodes" do
    node = insert_known_node("known-import-node")

    configuration = %Configuration{
      nodes_settings: %{
        "known-import-node" => %{"web_ui" => "https://known.example"},
        "unknown-import-node" => %{"web_ui" => "https://unknown.example"},
        "has spaces" => %{"web_ui" => "https://invalid.example"}
      }
    }

    state = %State{}
    payload = %Mutation{domain: :settings, action: :import, data: configuration}

    assert %Outcome{
             state: %State{},
             broadcast_opts: [delayed: false, force: true],
             effects: [],
             operation_result: %{status: :completed, import_report: %Report{skipped: 2}}
           } =
             execute_plan(SettingsDomain, state, payload)

    assert %Node.Settings{web_ui: "https://known.example"} = NodePersistence.load_settings(node)
    assert Exdock.Repo.get_by(Exdock.Database.NodeSettings, node: "unknown-import-node") == nil
  end

  test "change/2 imports only valid image metadata overrides" do
    configuration = %Configuration{
      repository_overrides: %{
        "example/app:latest" => %{"repository_url" => "https://example.com/app"},
        "" => %{"repository_url" => "https://example.com/empty"},
        "example/not-a-map:latest" => "invalid"
      }
    }

    payload = %Mutation{domain: :settings, action: :import, data: configuration}

    assert %Outcome{
             state: %State{},
             broadcast_opts: [delayed: false, force: true],
             effects: [],
             operation_result: %{status: :completed, import_report: %Report{skipped: 0}}
           } =
             execute_plan(SettingsDomain, %State{}, payload)

    assert %Metadata{repository_url: "https://example.com/app"} =
             ImageMetadata.load("example/app:1.0.0")

    assert ImageMetadata.load("") == nil
    assert ImageMetadata.load("example/not-a-map:latest") == nil
  end

  test "import/1 ignores malformed top-level sections while importing user settings" do
    user = UserSettings.default_user()

    configuration = %Configuration{
      user_settings: %{"automation_enabled" => true},
      nodes_settings: "not a map",
      images_settings: 123,
      containers_settings: "invalid",
      repository_overrides: 10
    }

    assert {:ok,
            %Report{
              applied: %{user_settings: 1},
              skipped: 4,
              warnings: warnings
            }} = Settings.Importer.import(configuration)

    assert length(warnings) == 4

    assert %UserSettings{automation_enabled: true} = UserSettingsPersistence.load(user)
  end

  test "import/1 treats omitted user settings as optional" do
    node = insert_known_node("known-import-node-without-user-settings")

    configuration = %Configuration{
      nodes_settings: %{
        "known-import-node-without-user-settings" => %{"web_ui" => "https://known.example"}
      }
    }

    log =
      capture_log(fn ->
        assert {:ok, %Report{skipped: 0, warnings: []}} = Settings.Importer.import(configuration)
      end)

    refute log =~ "unexpected user settings format"
    assert %Node.Settings{web_ui: "https://known.example"} = NodePersistence.load_settings(node)
  end

  test "import/1 rejects a non-object payload without purging existing settings" do
    user = UserSettings.default_user()
    existing = UserSettings.default() |> UserSettings.set(:automation_enabled, true)
    assert {:ok, _record} = UserSettingsPersistence.insert(existing)

    assert {:error, :invalid_top_level_configuration} = Settings.Importer.import("[]")
    assert %UserSettings{automation_enabled: true} = UserSettingsPersistence.load(user)
  end

  test "import/1 keeps JSON input as a compatibility boundary" do
    user = UserSettings.default_user()
    json = Jason.encode!(%{"user_settings" => %{"automation_enabled" => true}})

    assert {:ok, %Report{applied: %{user_settings: 1}, skipped: 0}} =
             Settings.Importer.import(json)

    assert %UserSettings{automation_enabled: true} = UserSettingsPersistence.load(user)
  end

  test "change/2 imports image and container settings for known runtime nodes only" do
    node = insert_known_node("import-node")

    configuration = %Configuration{
      images_settings: %{
        "import-node" => %{
          "valid/app:1.0.0" => %{"delete_lock" => true},
          "invalid" => "wrong"
        },
        "unknown-import-node" => %{
          "missing/app:1.0.0" => %{"delete_lock" => true}
        }
      },
      containers_settings: %{
        "import-node" => %{
          "container-a" => %{"priority" => 5, "labels" => ["blue"]},
          "invalid-container" => "wrong"
        },
        "unknown-import-node" => %{
          "container-b" => %{"priority" => 4}
        }
      }
    }

    payload = %Mutation{domain: :settings, action: :import, data: configuration}

    assert %Outcome{
             state: %State{},
             broadcast_opts: [delayed: false, force: true],
             effects: [],
             operation_result: %{status: :completed, import_report: %Report{skipped: 2}}
           } =
             execute_plan(SettingsDomain, %State{}, payload)

    assert %ImageSettings{delete_lock: true} =
             ImageSettingsPersistence.load(node, "valid/app:1.0.0")

    assert ImageSettingsPersistence.load(node, "invalid") == nil
    assert ImageSettingsPersistence.load("unknown-import-node", "missing/app:1.0.0") == nil

    assert %ContainerSettings{priority: 5} =
             ContainerSettingsPersistence.load(node, "container-a")

    assert ContainerSettingsPersistence.load(node, "invalid-container") == nil
    assert ContainerSettingsPersistence.load("unknown-import-node", "container-b") == nil
  end

  defp insert_known_node(node) do
    node
    |> Node.default()
    |> Node.set_fetched_at(DateTime.utc_now())
    |> NodePersistence.insert()

    node
  end

  defp execute_plan(domain, state, %Mutation{} = mutation) do
    {:ok, data} =
      MutationContract.normalize_payload(mutation.domain, mutation.action, mutation.data)

    domain.plan(state, %{mutation | data: data}) |> Plan.execute()
  end
end
