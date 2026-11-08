defmodule Exdock.Runtime.Command.Repository do
  @moduledoc false

  @behaviour Exdock.Runtime.Command.Handler

  alias Exdock.Server.Jobs
  alias Exdock.Server.State

  @actions [:fetch_repositories, :fetch_releases]

  defstruct [:action, :repositories, :filter]

  @type t :: %__MODULE__{
          action: :fetch_repositories | :fetch_releases,
          repositories: [String.t()] | nil,
          filter: [atom()] | nil
        }

  @spec fetch([String.t()]) :: t()
  def fetch(repositories),
    do: %__MODULE__{
      action: :fetch_repositories,
      repositories: repositories
    }

  @spec fetch_releases([atom()]) :: t()
  def fetch_releases(filter \\ [:ok, :rate_limit]),
    do: %__MODULE__{action: :fetch_releases, filter: filter}

  @impl true
  def kind(%__MODULE__{action: action}) when action in @actions, do: action

  @impl true
  def normalize(
        %__MODULE__{
          action: :fetch_repositories,
          repositories: repositories
        } = command
      )
      when is_list(repositories),
      do: {:ok, command}

  def normalize(%__MODULE__{action: :fetch_releases, filter: filter} = command)
      when is_list(filter),
      do: {:ok, command}

  def normalize(%__MODULE__{}), do: {:error, :invalid_command}

  @impl true
  def execute(
        %State{} = state,
        %__MODULE__{
          action: :fetch_repositories,
          repositories: repositories
        }
      ),
      do: work(Jobs.Local.Releases.fetch_repositories(state, repositories))

  def execute(
        %State{} = state,
        %__MODULE__{action: :fetch_releases, filter: filter}
      ),
      do: work(Jobs.Local.Releases.fetch_cluster(state, filter))

  defp work(work), do: {:work, work}
end
