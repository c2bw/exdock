defmodule Exdock.Domain.Container do
  @moduledoc """
  The container data is composed of multiple parts.

  - `core`: the core data of the container, including the image data and settings
  - `extended`: the extended data of the container, ephemeral data such as logs and resources

  Note that a (running) Docker container requires an image to be associated with it, this module is dependent on the image data.
  """
  alias Exdock.Container.AutomationPolicy
  alias Exdock.Protocol.Snapshot, as: Client
  alias Exdock.Domain.Container.Core
  alias Exdock.Domain.Container.Core.ImageData
  alias Exdock.Domain.Container
  alias Exdock.Domain.Container.{Extended, Resources, Settings}
  alias Exdock.Domain
  alias Exdock.Domain.Image
  alias Exdock.Domain.TagInfo

  defstruct [:node, :name, :id, :core, :extended]

  @type t :: %__MODULE__{
          # Identifiers
          node: String.t(),
          name: String.t(),
          id: String.t(),
          # Data
          core: Core.t(),
          extended: Extended.t()
        }

  @doc """
  Create a container struct from container data received from the client.
  """
  @spec from_client(
          String.t(),
          Client.Container.t(),
          t() | nil,
          Domain.Image.t(),
          Domain.TagInfo.t(),
          boolean(),
          DateTime.t()
        ) :: t()
  def from_client(
        node,
        %Client.Container{name: name, id: id, resources: resources} = container,
        previous,
        %Domain.Image{} = image,
        %Domain.TagInfo{} = tag_info,
        image_is_present,
        %DateTime{} = fetched_at
      ) do
    is_deleted = false
    # Preserve settings and rolling extended metrics only when this is the same
    # Docker container id; a recreated container starts fresh runtime history.
    {settings, extended} = inherited_settings_and_extended(previous, id, resources, fetched_at)
    core = Container.Core.new(container, tag_info, image, settings, image_is_present, is_deleted, fetched_at)

    %__MODULE__{
      node: node,
      name: name,
      id: id,
      core: core,
      extended: extended
    }
  end

  defp inherited_settings_and_extended(nil, id, _resources, %DateTime{}) when is_binary(id),
    do: {Settings.default(), Container.Extended.new()}

  defp inherited_settings_and_extended(%__MODULE__{} = previous, id, resources, %DateTime{} = now)
       when is_binary(id) do
    {get_settings(previous), inherited_extended(previous.id, id, previous.extended, resources, now)}
  end

  defp inherited_extended(previous_id, current_id, extended, resources, now) do
    if same_container_id?(previous_id, current_id) do
      append_resource_sample(extended, resources, now)
    else
      Container.Extended.new()
    end
  end

  defp append_resource_sample(%Extended{} = extended, nil, %DateTime{}), do: extended

  defp append_resource_sample(%Extended{} = extended, %{} = resources, %DateTime{} = now),
    do: append_resource_record(extended, Resources.Record.new(resources), now)

  defp append_resource_record(%Extended{} = extended, nil, %DateTime{}), do: extended

  defp append_resource_record(%Extended{} = extended, %Resources.Record{} = record, %DateTime{} = now),
    do: Container.Extended.add_record(extended, record, now)

  defp same_container_id?(previous_id, current_id) when is_binary(previous_id) and is_binary(current_id),
    do: previous_id == current_id

  @spec update(t(), Domain.Image.t(), Domain.TagInfo.t(), boolean()) :: t()
  def update(
        %__MODULE__{core: %Core{} = previous_core} = container,
        %Domain.Image{} = image,
        %TagInfo{} = tag_info,
        image_is_present
      ) do
    # Updates refresh image/tag status while preserving identity, settings, and
    # extended runtime history.
    new_core = previous_core |> Core.update(tag_info, image, image_is_present)
    %{container | core: new_core}
  end

  @spec priority(t()) :: integer()
  def priority(%__MODULE__{core: %Core{settings: %Settings{priority: priority}}} = _), do: priority
  @spec image_id(t()) :: String.t()
  def image_id(%__MODULE__{core: %Core{image_data: %ImageData{image: %Image{id: id}}}} = _), do: id
  @spec image_tag(t()) :: String.t()
  def image_tag(%__MODULE__{core: %Core{image_data: %ImageData{tag_info: %TagInfo{tag: tag}}}} = _), do: tag
  @spec image_status(t()) :: Core.ImageData.status()
  def image_status(%__MODULE__{core: %Core{image_data: %ImageData{status: status}}} = _), do: status
  @spec running?(t()) :: boolean()
  def running?(%__MODULE__{core: %Core{is_running: is_running}} = _), do: is_running
  @spec restarting?(t()) :: boolean()
  def restarting?(%__MODULE__{core: %Core{state: %Core.State{restarting: r}}} = _), do: r == true

  @spec set_settings(t(), Container.Settings.t()) :: t()
  def set_settings(%__MODULE__{core: core} = container, settings), do: %{container | core: %{core | settings: settings}}

  @spec set_logs(t(), [String.t()], DateTime.t()) :: t()
  def set_logs(%__MODULE__{extended: extended} = container, logs, %DateTime{} = occurred_at),
    do: %{container | extended: Extended.set_logs(extended, logs, occurred_at)}

  @spec set_resources(t(), Resources.Record.t()) :: t()
  def set_resources(%__MODULE__{extended: e} = c, %Resources.Record{time: now} = r),
    do: %{c | extended: Extended.add_record(e, r, now)}

  @spec get_settings(t()) :: Container.Settings.t()
  def get_settings(%__MODULE__{core: %Core{settings: settings}} = _), do: settings

  @doc """
  Check if the container can be auto-updated.
  """
  @spec can_auto_update?(t(), integer()) :: boolean()
  def can_auto_update?(
        %__MODULE__{
          core: %Core{
            is_running: running?,
            image_data: %ImageData{status: image_status},
            settings: %Settings{priority: priority, auto_update: policy}
          }
        },
        threshold
      ) do
    AutomationPolicy.eligible?(priority, policy, threshold, running?, image_status)
  end

  @doc """
  Rebuilds a runtime container from persistence-neutral durable attributes.
  """
  @spec from_persisted(map(), Domain.Node.t(), Image.t(), TagInfo.t(), Settings.t(), boolean()) :: t()
  def from_persisted(
        %{node: node, id: id, name: name} = attributes,
        %Domain.Node{fetched_at: fetched_at},
        %Image{} = image,
        %TagInfo{} = tag_info,
        %Settings{} = settings,
        image_present_on_node
      )
      when is_binary(id) and is_boolean(image_present_on_node) do
    %__MODULE__{
      node: node,
      name: name,
      id: id,
      core: Core.from_persisted(attributes, tag_info, image, settings, image_present_on_node, fetched_at),
      extended: Extended.new()
    }
  end
end
