defmodule Exdock.Repo.Migrations.CreateSettings do
  use Ecto.Migration

  def change do
    create table(:user_settings, primary_key: false) do
      add :user, :string, null: false, primary_key: true
      add :pageload_node_refresh, :boolean, null: false
      add :aesthetic_page, :boolean, null: false
      add :rendering_statistics, :boolean, null: false
      add :container_resources, :boolean, null: false
      add :automation_enabled, :boolean, null: false
      add :auto_update_above, :integer, null: false
      add :auto_update_containers, :boolean, null: false
      add :auto_update_releases, :boolean, null: false
      add :cron_string, :string, null: false
    end

    create table(:node_settings, primary_key: false) do
      add :node, :string, null: false, primary_key: true
      add :web_ui, :string, null: false
    end
  end
end
