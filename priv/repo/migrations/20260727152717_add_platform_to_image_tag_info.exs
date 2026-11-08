defmodule Exdock.Repo.Migrations.AddPlatformToImageTagInfo do
  use Ecto.Migration

  def up do
    # Registry metadata is a derived cache. Rebuild the table so the primary key
    # can change from `tag` to `{tag, platform}`; the next registry refresh
    # repopulates it with platform-aware entries.
    drop table(:image_tag_info)

    create table(:image_tag_info, primary_key: false) do
      add :tag, :string, null: false, primary_key: true
      add :platform, :string, null: false, primary_key: true
      add :latest_digest, :string, null: false
      add :latest_date, :utc_datetime, null: false
      add :check_date, :utc_datetime
    end
  end

  def down do
    drop table(:image_tag_info)

    create table(:image_tag_info, primary_key: false) do
      add :tag, :string, null: false, primary_key: true
      add :latest_digest, :string, null: false
      add :latest_date, :utc_datetime, null: false
      add :check_date, :utc_datetime
    end
  end
end
