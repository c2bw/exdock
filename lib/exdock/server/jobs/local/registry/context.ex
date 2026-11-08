defmodule Exdock.Server.Jobs.Local.Registry.Context do
  @moduledoc """
  Runtime collaborators used while fetching registry metadata.

  The default context connects registry jobs to the remote Docker client, the
  shared registry limiter, the system clock, and job progress delivery. Tests
  can replace those boundaries without changing the concurrent executor.
  """

  alias Exdock.Server.{Jobs, RegistryFetchLimiter}
  alias Exdock.Server.Jobs.Local.Registry.RemoteMetadata
  alias Exdock.Domain.TagInfo

  @type metadata_lookup ::
          (String.t(), String.t(), TagInfo.t() | nil -> {String.t(), DateTime.t()})
  @type clock :: (-> DateTime.t())
  @type update_publisher :: (Jobs.Update.t() -> term())

  @enforce_keys [:metadata_lookup, :clock, :update_publisher, :max_concurrency]
  defstruct [:metadata_lookup, :clock, :update_publisher, :max_concurrency]

  @type t :: %__MODULE__{
          metadata_lookup: metadata_lookup(),
          clock: clock(),
          update_publisher: update_publisher(),
          max_concurrency: pos_integer()
        }

  @doc """
  Returns the production registry fetch context.
  """
  @spec default() :: t()
  def default do
    %__MODULE__{
      metadata_lookup: &fetch_metadata/3,
      clock: &DateTime.utc_now/0,
      update_publisher: &Jobs.job_update/1,
      max_concurrency: RegistryFetchLimiter.max_concurrency()
    }
  end

  @doc """
  Builds a context by replacing selected production collaborators.
  """
  @spec new(keyword()) :: t()
  def new(overrides \\ []) when is_list(overrides) do
    default()
    |> struct!(overrides)
    |> validate!()
  end

  @spec lookup_metadata(t(), String.t(), String.t(), TagInfo.t() | nil) ::
          {String.t(), DateTime.t()}
  def lookup_metadata(%__MODULE__{metadata_lookup: lookup}, image_tag, platform, previous_tag_info),
    do: lookup.(image_tag, platform, previous_tag_info)

  @spec now(t()) :: DateTime.t()
  def now(%__MODULE__{clock: clock}), do: clock.()

  @spec publish_update(t(), Jobs.Update.t()) :: term()
  def publish_update(%__MODULE__{update_publisher: publisher}, %Jobs.Update{} = update),
    do: publisher.(update)

  defp fetch_metadata(image_tag, platform, previous_tag_info) do
    RegistryFetchLimiter.run(image_tag, fn ->
      RemoteMetadata.fetch(image_tag, platform, previous_tag_info)
    end)
  end

  defp validate!(
         %__MODULE__{
           metadata_lookup: metadata_lookup,
           clock: clock,
           update_publisher: update_publisher,
           max_concurrency: max_concurrency
         } = context
       )
       when is_function(metadata_lookup, 3) and is_function(clock, 0) and
              is_function(update_publisher, 1) and is_integer(max_concurrency) and
              max_concurrency > 0,
       do: context

  defp validate!(_context), do: raise(ArgumentError, "invalid registry fetch context")
end
