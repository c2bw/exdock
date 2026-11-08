defmodule Exdock.ReadModel.Page do
  @moduledoc """
  Stable page-level projection consumed by LiveViews.

  Every page receives the same base runtime, configuration, and activity
  fields. Optional collection fields are populated only when requested.
  """

  alias Exdock.Configuration
  alias Exdock.ReadModel.{ClusterNode, Container, Image, Repository}
  alias Exdock.Server.Logging.{Log, Status}

  defstruct runtime_revision: 0,
            activity_revision: 0,
            server_configuration: nil,
            user_settings: nil,
            nodes_list: [],
            status: nil,
            log: [],
            nodes: nil,
            containers: nil,
            containers_extended: nil,
            images: nil,
            repositories: nil,
            cluster_info: nil

  @base_assigns [
    :runtime_revision,
    :activity_revision,
    :server_configuration,
    :user_settings,
    :nodes_list,
    :status,
    :log
  ]

  @spec to_assigns(t(), [atom()]) :: map()
  def to_assigns(%__MODULE__{} = page, projections) when is_list(projections) do
    projection_assigns = Exdock.ReadModel.Projections.assigns(projections)
    page |> Map.from_struct() |> Map.take(@base_assigns ++ projection_assigns)
  end

  @type t :: %__MODULE__{
          runtime_revision: non_neg_integer(),
          activity_revision: non_neg_integer(),
          server_configuration: Configuration.t(),
          user_settings: Configuration.settings() | nil,
          nodes_list: [String.t()],
          status: Status.t(),
          log: [Log.t()],
          nodes: %{String.t() => ClusterNode.t()} | nil,
          containers: %{String.t() => [Container.t()]} | nil,
          containers_extended: %{String.t() => %{Container.Key.t() => Container.Extended.t()}} | nil,
          images: %{String.t() => [Image.t()]} | nil,
          repositories: [Repository.t()] | nil,
          cluster_info: map() | nil
        }
end
