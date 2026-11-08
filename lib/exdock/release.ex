defmodule Exdock.Release do
  @app :exdock

  require Logger

  def migrate do
    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    for r <- repos(), r == repo do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
    end
  end

  def create do
    for repo <- repos() do
      config = repo.config()
      ensure_database_directory!(repo, config)

      case storage_up(repo, config) do
        :ok ->
          Logger.info("The database for #{inspect(repo)} has been created")

        {:error, :already_up} ->
          Logger.info("The database for #{inspect(repo)} has already been created")

        {:error, term} when is_binary(term) ->
          err = "The database for #{inspect(repo)} couldn't be created: #{term}"
          Logger.error(err)
          raise err

        {:error, term} ->
          err = "The database for #{inspect(repo)} couldn't be created: #{inspect(term)}"
          Logger.error(err)
          raise err
      end
    end
  end

  defp ensure_database_directory!(repo, config) do
    case Keyword.fetch(config, :database) do
      {:ok, database} when is_binary(database) ->
        directory = database |> Path.expand() |> Path.dirname()

        case File.mkdir_p(directory) do
          :ok ->
            :ok

          {:error, reason} ->
            raise """
            The database directory for #{inspect(repo)} could not be created.
            Database: #{database}
            Directory: #{directory}
            Reason: #{:file.format_error(reason)}
            Ensure the directory is mounted and writable by the Exdock process.
            """
        end

      _ ->
        :ok
    end
  end

  defp storage_up(repo, config) do
    repo.__adapter__().storage_up(config)
  rescue
    exception ->
      database = Keyword.get(config, :database, "unknown")

      raise """
      The database for #{inspect(repo)} could not be opened.
      Database: #{database}
      Reason: #{Exception.message(exception)}
      Ensure the database's parent directory exists and is writable by the Exdock process.
      """
  end

  defp repos do
    Application.load(@app)
    Application.fetch_env!(@app, :ecto_repos)
  end
end
