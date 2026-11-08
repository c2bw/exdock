defmodule Exdock.ReadModel.Container.Core do
  @moduledoc """
  Public, persistence-neutral container summary used by delivery layers.
  """

  alias Exdock.Container.SettingsCatalog
  alias Exdock.ReadModel.Value

  @fields [
    :is_running,
    :stack_name,
    :configuration,
    :state,
    :json_compressed_inspect,
    :image_data,
    :settings,
    :is_deleted,
    :fetched_at,
    :image_status,
    :image_tag,
    :image_url,
    :image_size,
    :image_size_human,
    :image_present_on_node,
    :image_build_date,
    :remote_image_date,
    :repository_url
  ]

  @enforce_keys @fields
  defstruct @fields

  @type image_status :: :unknown | :updated | :outdated | :empty_local_digest | :empty_remote_digest
  @type settings :: %{
          required(:priority) => integer(),
          required(:auto_update) => SettingsCatalog.auto_update(),
          required(:labels) => [String.t()]
        }
  @type state :: %{
          required(:started_at) => DateTime.t() | nil,
          required(:finished_at) => DateTime.t() | nil,
          required(:restarting) => boolean() | nil,
          optional(atom()) => term()
        }
  @type configuration :: %{
          required(:networks) => map() | nil,
          required(:ports) => map() | nil,
          optional(atom()) => term()
        }

  @type t :: %__MODULE__{
          is_running: boolean(),
          stack_name: String.t(),
          configuration: configuration(),
          state: state(),
          json_compressed_inspect: binary(),
          image_data: map(),
          settings: settings(),
          is_deleted: boolean(),
          fetched_at: DateTime.t(),
          image_status: image_status(),
          image_tag: String.t(),
          image_url: String.t(),
          image_size: non_neg_integer(),
          image_size_human: String.t(),
          image_present_on_node: boolean(),
          image_build_date: DateTime.t(),
          remote_image_date: DateTime.t(),
          repository_url: String.t() | nil
        }

  @spec from_domain(map() | t()) :: t()
  def from_domain(%__MODULE__{} = core), do: core

  def from_domain(
        %{
          is_running: is_running,
          stack_name: stack_name,
          configuration: configuration,
          state: state,
          json_compressed_inspect: json_compressed_inspect,
          image_data: image_data,
          settings: settings,
          is_deleted: is_deleted,
          fetched_at: fetched_at
        } = core
      )
      when is_boolean(is_running) and is_binary(stack_name) and is_map(configuration) and
             is_map(state) and is_binary(json_compressed_inspect) and is_map(image_data) and
             is_map(settings) and is_boolean(is_deleted) and is_struct(fetched_at, DateTime) do
    projected = Value.project(core)

    projected
    |> Map.take(@fields)
    |> Map.merge(image_display_fields(projected))
    |> then(&struct!(__MODULE__, &1))
  end

  defp image_display_fields(%{
         image_data: %{image: image, tag_info: tag_info, present_on_node: present?, status: status}
       }) do
    %{
      image_status: status,
      image_tag: Map.get(tag_info, :tag),
      image_url: Map.get(image, :registry_url),
      image_size: Map.get(image, :size),
      image_size_human: Map.get(image, :size_human),
      image_present_on_node: present?,
      image_build_date: Map.get(image, :build_date),
      remote_image_date: Map.get(tag_info, :latest_date),
      repository_url: get_in(image, [:metadata, :repository_url])
    }
  end

  defp image_display_fields(_core), do: %{}
end
