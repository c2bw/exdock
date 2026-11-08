defmodule Exdock.Repo.Migrations.CreateContainersAndImages do
  use Ecto.Migration

  def change do
    # Create the nodes table
    create table(:nodes, primary_key: false) do
      add :node, :string, null: false, primary_key: true
      add :fetched_at, :utc_datetime, null: false
    end

    # Create the images tables
    create table(:image_tag_info, primary_key: false) do
      add :tag, :string, null: false, primary_key: true
      add :latest_digest, :string, null: false
      add :latest_date, :utc_datetime, null: false
      add :check_date, :utc_datetime
    end

    create table(:image_metadata, primary_key: false) do
      add :name, :string, null: false, primary_key: true
      add :repository_url, :string, null: false
    end

    create table(:image_settings, primary_key: false) do
      add :id, :string, null: false, primary_key: true
      add :node, :string, null: false, primary_key: true
      add :delete_lock, :boolean
    end

    create table(:images, primary_key: false) do
      add :node, :string, null: false, primary_key: true
      add :id, :string, null: false, primary_key: true
      add :image_key, :string, null: false
      add :name, :string, null: false
      add :tags, :string, null: false
      add :digest, :string
      add :size, :integer
      add :shared_size, :integer
      add :build_date, :utc_datetime
    end

    create table(:repository_releases, primary_key: false) do
      add :url, :string, null: false, primary_key: true
      add :version, :string, null: false, primary_key: true
      add :release_url, :string, null: false
      add :source, :string, null: false
      add :name, :string, null: false
      add :description, :binary
      add :time_released, :utc_datetime, null: false
    end

    create table(:repositories, primary_key: false) do
      add :url, :string, null: false, primary_key: true
      add :releases_page, :string
      add :last_check, :utc_datetime
    end

    create unique_index(:images, [:image_key])

    # Create the containers tables
    create table(:container_settings, primary_key: false) do
      add :node, :string, null: false, primary_key: true
      add :name, :string, null: false, primary_key: true
      add :priority, :integer, null: false
      add :auto_update, :string, null: false
      add :labels, {:array, :string}, null: false
    end

    create table(:containers, primary_key: false) do
      add :node, :string, null: false, primary_key: true
      add :name, :string, null: false, primary_key: true

      add :image_key,
          references(:images, column: :image_key, type: :string, on_delete: :delete_all)

      add :id, :string, null: false
      add :is_running, :boolean, null: false
      add :stack_name, :string
      add :configuration, :binary
      add :state, :string
      add :image_tag, :string
      add :image_id, :string, null: false
      add :image_status, :string
      add :is_deleted, :boolean, null: false
    end

    create index(:containers, [:image_key])
  end
end
