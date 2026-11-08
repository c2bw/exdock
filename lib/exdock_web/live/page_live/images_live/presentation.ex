defmodule ExdockWeb.ImagesLive.Presentation do
  @moduledoc """
  Builds the stable image inventory data consumed by the images page.

  The page clock changes independently of the image projection, so inventory
  counts and registry grouping belong at the projection boundary rather than
  in render functions.
  """

  alias Exdock.ReadModel.Image

  @type summary :: %{
          total: non_neg_integer(),
          used: non_neg_integer(),
          unused: non_neg_integer(),
          locked: non_neg_integer()
        }

  @spec build([map()]) :: %{summary: summary(), registries: [{String.t(), pos_integer()}]}
  def build(images) when is_list(images) do
    {summary, registry_counts} =
      Enum.reduce(images, {empty_summary(), %{}}, fn image, {summary, registries} ->
        locked? = delete_locked?(image)
        used? = in_use?(image)

        summary = %{
          total: summary.total + 1,
          used: summary.used + flag(used?),
          unused: summary.unused + flag(not used? and not locked?),
          locked: summary.locked + flag(locked?)
        }

        provider = Image.categorize_registry(image.name)
        {summary, Map.update(registries, provider, 1, &(&1 + 1))}
      end)

    registries = Enum.sort_by(registry_counts, fn {provider, count} -> {-count, provider} end)
    %{summary: summary, registries: registries}
  end

  @spec node_rows(map()) :: [{String.t(), map()}]
  def node_rows(%{by_node_string: nodes}) when is_map(nodes), do: Enum.sort(nodes)
  def node_rows(_cluster_info), do: []

  defp empty_summary, do: %{total: 0, used: 0, unused: 0, locked: 0}
  defp flag(true), do: 1
  defp flag(false), do: 0

  defp in_use?(%{in_use: in_use}) when is_boolean(in_use), do: in_use
  defp in_use?(_), do: false

  defp delete_locked?(%{delete_lock: lock}) when is_boolean(lock), do: lock
  defp delete_locked?(%{settings: %{delete_lock: lock}}) when is_boolean(lock), do: lock
  defp delete_locked?(_), do: false
end
