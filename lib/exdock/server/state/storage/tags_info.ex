defmodule Exdock.Server.State.Storage.TagsInfo do
  @moduledoc """
  Stores latest registry tag metadata keyed by full image tag and OCI platform.

  Tag refreshes arrive as batches from registry jobs. Each tag is compared
  against the current accumulator before being stored so notifications are only
  emitted for genuinely newer metadata, even when a single batch contains
  multiple updates for the same tag.
  """

  alias Exdock.Server.State.Storage.Persistence.TagInfo, as: TagInfoPersistence
  alias Exdock.Server.State.Storage.Persistence.{Result, Transaction}
  alias Exdock.Domain

  defstruct [
    :tags
  ]

  @type t :: %__MODULE__{
          tags: %{{String.t(), String.t()} => Domain.TagInfo.t()}
        }

  @spec load() :: t()
  def load() do
    %__MODULE__{
      tags: load_tag_map()
    }
  end

  @spec get(t(), String.t(), String.t()) :: Domain.TagInfo.t() | nil
  def get(%__MODULE__{tags: tags} = _, tag, platform)
      when is_binary(tag) and is_binary(platform),
      do: Map.get(tags, {tag, platform})

  @spec set(t(), Domain.TagInfo.t()) :: {:ok, t()} | {:error, term()}
  def set(%__MODULE__{} = tags_info, %Domain.TagInfo{} = tag_info) do
    if stale_observation?(tags_info, tag_info) do
      {:ok, tags_info}
    else
      case persist_tag_info(tag_info) do
        :ok -> {:ok, put_tag(tags_info, tag_info)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp persist_tag_info(%Domain.TagInfo{} = tag_info) do
    tag_info
    |> TagInfoPersistence.insert(on_conflict: :replace_all)
    |> Result.normalize_write_result(:tag_info_upsert)
  end

  defp load_tag_map do
    TagInfoPersistence.load_all()
    |> Map.new(fn %Domain.TagInfo{tag: tag, platform: platform} = tag_info ->
      {{tag, platform}, tag_info}
    end)
  end

  @doc """
  Return true when the stored tag metadata exists and is older than `tag_info`.

  Missing tags do not count as newer because there is no previous state to
  notify about; the first observation is simply cached.
  """
  @spec newer?(t(), Domain.TagInfo.t()) :: boolean()
  def newer?(
        %__MODULE__{} = tags_info,
        %Domain.TagInfo{
          tag: tag,
          platform: platform,
          latest_date: check_date
        }
      ) do
    case get(tags_info, tag, platform) do
      nil -> false
      %Domain.TagInfo{latest_date: old_date} -> newer_date?(check_date, old_date)
    end
  end

  defp newer_date?(%DateTime{} = check_date, %DateTime{} = old_date), do: DateTime.compare(check_date, old_date) == :gt

  @spec apply_updates(t(), [Domain.TagInfo.t()]) ::
          {:ok, t(), [Domain.TagInfo.t()]} | {:error, term()}
  def apply_updates(%__MODULE__{} = tags, tags_list) when is_list(tags_list) do
    {updated_tags, accepted, notifications} = apply_tag_updates(tags, tags_list)

    case persist_tag_updates(accepted) do
      :ok ->
        {:ok, updated_tags, notifications}

      {:error, reason} ->
        {:error, {:tag_info_persistence, reason}}
    end
  end

  defp persist_tag_updates(tags_list) do
    Transaction.run_each(tags_list, &persist_tag_info/1)
  end

  defp apply_tag_updates(%__MODULE__{} = tags, tags_list) when is_list(tags_list) do
    {tags, accepted, notifications} =
      Enum.reduce(tags_list, {tags, [], []}, fn tag_info, {current_tags, accepted, notifications} = acc ->
        if stale_observation?(current_tags, tag_info) do
          acc
        else
          notifications = if newer?(current_tags, tag_info), do: [tag_info | notifications], else: notifications
          {put_tag(current_tags, tag_info), [tag_info | accepted], notifications}
        end
      end)

    {tags, Enum.reverse(accepted), Enum.reverse(notifications)}
  end

  # Freshness is the observation time, not the image's build date: a newer
  # observation may legitimately report a registry tag rolled back to an older image.
  defp stale_observation?(tags, %Domain.TagInfo{tag: tag, platform: platform, check_date: observed_at}) do
    case get(tags, tag, platform) do
      %Domain.TagInfo{check_date: %DateTime{} = current} ->
        is_nil(observed_at) or DateTime.compare(observed_at, current) == :lt

      _no_observation ->
        false
    end
  end

  defp put_tag(
         %__MODULE__{tags: tags} = tags_info,
         %Domain.TagInfo{tag: tag, platform: platform} = tag_info
       ) do
    %{tags_info | tags: Map.put(tags, {tag, platform}, tag_info)}
  end
end
