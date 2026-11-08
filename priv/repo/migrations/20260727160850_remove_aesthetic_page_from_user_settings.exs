defmodule Exdock.Repo.Migrations.RemoveAestheticPageFromUserSettings do
  use Ecto.Migration

  def change do
    alter table(:user_settings) do
      remove :aesthetic_page, :boolean
    end
  end
end
