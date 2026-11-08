defmodule Exdock.Domain.Container.Core do
  alias Exdock.Protocol.Snapshot, as: Client
  alias Exdock.Domain
  alias Exdock.Domain.Container.Core.ImageData
  alias Exdock.Domain.Container.Core.State
  alias Exdock.Domain.Container.Configuration
  alias Exdock.Domain.Container.Settings

  @derive Jason.Encoder
  defstruct [
    :is_running,
    :stack_name,
    :configuration,
    :state,
    :json_compressed_inspect,
    :image_data,
    :settings,
    :is_deleted,
    fetched_at: nil
  ]

  @type t :: %__MODULE__{
          # Container information
          is_running: boolean(),
          stack_name: String.t(),
          configuration: Configuration.t(),
          state: State.t(),
          json_compressed_inspect: String.t(),
          # Image data
          image_data: ImageData.t(),
          # Display data
          settings: Settings.t(),
          is_deleted: boolean(),
          fetched_at: DateTime.t()
        }

  @doc """
  New core struct from container and image information.
  """
  @spec new(Client.Container.t(), Domain.TagInfo.t(), Domain.Image.t(), Settings.t(), boolean(), boolean(), DateTime.t()) ::
          t()
  def new(
        %Client.Container{
          inspect: %{"State" => state} = inspect,
          is_running: is_running,
          stack_name: stack_name
        },
        %Domain.TagInfo{} = tag_info,
        %Domain.Image{} = image,
        %Settings{} = settings,
        image_is_present,
        is_deleted,
        %DateTime{} = fetched_at
      )
      when is_map(state) and is_boolean(is_deleted) and is_boolean(image_is_present) do
    inspect
    |> core_fields_from_inspect()
    |> build_core(
      is_running,
      stack_name,
      settings,
      image_data(tag_info, image, image_is_present),
      is_deleted,
      fetched_at
    )
  end

  @doc """
  Rebuilds a core projection from persistence-neutral durable attributes.
  """
  @spec from_persisted(
          map(),
          Domain.TagInfo.t(),
          Domain.Image.t(),
          Settings.t(),
          boolean(),
          DateTime.t()
        ) :: t()
  def from_persisted(
        %{
          is_running: is_running,
          stack_name: stack_name,
          state: state,
          is_deleted: is_deleted,
          configuration: configuration
        },
        %Domain.TagInfo{} = tag_info,
        %Domain.Image{} = image,
        %Settings{} = settings,
        image_is_present,
        %DateTime{} = fetched_at
      )
      when is_boolean(image_is_present) do
    build_core(
      {configuration, State.from_persisted(state), "{}"},
      is_running,
      stack_name,
      settings,
      image_data(tag_info, image, image_is_present),
      is_deleted,
      fetched_at
    )
  end

  defp build_core(
         {%Configuration{} = configuration, %State{} = state, json_inspect},
         is_running,
         stack_name,
         %Settings{} = settings,
         %ImageData{} = image_data,
         is_deleted,
         %DateTime{} = fetched_at
       )
       when is_boolean(is_running) and (is_binary(stack_name) or is_nil(stack_name)) and
              is_binary(json_inspect) and
              is_boolean(is_deleted) do
    %__MODULE__{
      is_running: is_running,
      stack_name: stack_name || "",
      configuration: configuration,
      state: state,
      json_compressed_inspect: json_inspect |> :zlib.gzip(),
      image_data: image_data,
      settings: settings,
      is_deleted: is_deleted,
      fetched_at: fetched_at
    }
  end

  @doc """
  Update core struct with new information.
  """
  @spec update(t(), Domain.TagInfo.t(), Domain.Image.t(), boolean()) :: t()
  def update(
        %__MODULE__{} = core,
        %Domain.TagInfo{} = tag_info,
        %Domain.Image{} = image,
        image_is_present
      )
      when is_boolean(image_is_present) do
    %{core | image_data: image_data(tag_info, image, image_is_present)}
  end

  defp core_fields_from_inspect(%{"State" => state} = inspect) when is_map(state) do
    {Configuration.new(inspect), State.new(state), encode_inspect(inspect)}
  end

  defp image_data(tag_info, image, image_is_present),
    do: ImageData.new(tag_info, image, image_is_present)

  defp encode_inspect(inspect), do: JSON.encode!(inspect)
end
