defmodule Exdock.Repo.Migrations.AddRepoDigestsToImages do
  use Ecto.Migration

  def change do
    alter table(:images) do
      add :repo_digests, {:array, :string}, default: [], null: false
    end
  end
end
