defmodule ExdockWeb.PageLive.StatusModal.ViewModel do
  @moduledoc """
  Normalizes status dashboard state into the groups rendered by the modal.
  """

  alias Exdock.Status.Dashboard
  alias Exdock.Status.Dashboard.Row

  @type node_entry :: %{node: String.t(), state: :ok | :error}
  @type nodes :: %{awaiting?: boolean(), entries: [node_entry()]}
  @type progress :: %{
          title: String.t(),
          unit: String.t(),
          fetched: non_neg_integer(),
          total: non_neg_integer(),
          active?: boolean()
        }
  @type action_entry :: %{node: String.t(), item: String.t(), row: Row.t()}
  @type action :: %{
          label: String.t(),
          entries: [action_entry()],
          show_message?: boolean(),
          item_class: String.t()
        }
  @type action_group :: %{title: String.t(), actions: [action()], empty?: boolean()}

  @enforce_keys [:nodes, :progress, :action_groups, :has_errors?, :errors_log]
  defstruct [:nodes, :progress, :action_groups, :has_errors?, :errors_log]

  @type t :: %__MODULE__{
          nodes: nodes(),
          progress: [progress()],
          action_groups: [action_group()],
          has_errors?: boolean(),
          errors_log: [{String.t(), String.t()}]
        }

  @spec build(Dashboard.t(), boolean(), [{String.t(), String.t()}]) :: t()
  def build(dash, has_errors?, errors_log) do
    %__MODULE__{
      nodes: nodes(Map.fetch!(dash, :node_refresh)),
      progress: [
        progress("Fetch Registry", "images", Map.fetch!(dash, :registry_fetch)),
        progress("Fetch Releases", "repositories", Map.fetch!(dash, :releases_fetch))
      ],
      action_groups: [
        action_group("Containers", [
          action("Recreate", Map.fetch!(dash, :container_recreate), true),
          action("Start", Map.fetch!(dash, :container_start)),
          action("Stop", Map.fetch!(dash, :container_stop)),
          action("Restart", Map.fetch!(dash, :container_restart), true)
        ]),
        action_group("Images", [
          action("Pull", Map.fetch!(dash, :image_pull), true, "text-xs tracking-tighter"),
          action("Delete", Map.fetch!(dash, :image_delete), false, "text-xs tracking-tighter")
        ])
      ],
      has_errors?: has_errors?,
      errors_log: errors_log
    }
  end

  defp nodes(entries) do
    %{
      awaiting?: map_size(entries) > 0,
      entries:
        Enum.map(entries, fn {node, %Row{state: {state, _reason}}} ->
          %{node: to_string(node), state: state}
        end)
    }
  end

  defp progress(title, unit, entries) do
    totals =
      Enum.reduce(entries, %{fetched: 0, total: 0}, fn
        {_key, %Row{data: %{fetched: fetched, total: total}}}, acc ->
          %{fetched: acc.fetched + fetched, total: acc.total + total}
      end)

    %{
      title: title,
      unit: unit,
      fetched: totals.fetched,
      total: totals.total,
      active?: map_size(entries) > 0
    }
  end

  defp action_group(title, actions) do
    %{title: title, actions: actions, empty?: Enum.all?(actions, &(&1.entries == []))}
  end

  defp action(label, entries, show_message? \\ false, item_class \\ "text-sm") do
    %{
      label: label,
      entries:
        Enum.map(entries, fn {{node, item}, %Row{} = row} ->
          %{node: to_string(node), item: to_string(item), row: row}
        end),
      show_message?: show_message?,
      item_class: item_class
    }
  end
end
