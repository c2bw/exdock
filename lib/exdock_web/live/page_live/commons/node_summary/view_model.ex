defmodule ExdockWeb.Commons.NodeSummary.ViewModel do
  @moduledoc """
  Builds presentation-ready data for a node summary row.

  Keeping aggregation and formatting here lets the HEEx components remain
  stateless and prevents them from depending on storage structures.
  """

  alias Exdock.Size
  alias Exdock.Container.RuntimeState
  alias ExdockWeb.Commons.NodeSummary.ResourceSummary

  @type metric :: %{
          icon: String.t(),
          label: String.t(),
          value: String.t() | number(),
          detail: String.t()
        }
  @type status_item :: %{
          count: non_neg_integer(),
          label: String.t(),
          bar_color: String.t()
        }
  @type icon_item :: %{icon: String.t(), color: String.t()}

  @type t :: %__MODULE__{
          summary_type: :containers | :images,
          nodename: String.t(),
          platform: String.t() | nil,
          metrics: [metric()],
          resource_rows: [[metric()]],
          status: %{
            visible?: boolean(),
            items: [status_item()]
          },
          state_icons: %{restarting: icon_item() | nil, recently_started: icon_item() | nil},
          staleness: %{icon: String.t() | nil, color: String.t() | nil, text: String.t() | nil},
          actions: %{nodename: String.t(), web_ui: String.t(), registry_fetch?: boolean()}
        }

  defstruct [
    :summary_type,
    :nodename,
    :platform,
    :metrics,
    :resource_rows,
    :status,
    :state_icons,
    :staleness,
    :actions
  ]

  @spec new(map()) :: t()
  def new(assigns) when is_map(assigns) do
    summary_type = Map.fetch!(assigns, :summary_type)
    nodename = Map.fetch!(assigns, :nodename)
    info = Map.fetch!(assigns, :node_info)
    clock_now = Map.fetch!(assigns, :clock_now)

    %__MODULE__{
      summary_type: summary_type,
      nodename: nodename,
      platform: Map.get(Map.get(assigns, :node_metadata, %{}), "platform"),
      metrics: metrics(summary_type, info),
      resource_rows:
        Map.get(assigns, :resource_rows) ||
          resource_rows(summary_type, Map.get(assigns, :containers_extended, %{})),
      status: status(summary_type, info),
      state_icons: state_icons(summary_type, info, clock_now),
      staleness: staleness(Map.get(assigns, :fetch_staleness), Map.get(assigns, :since_last_fetch)),
      actions: %{
        nodename: nodename,
        web_ui: Map.fetch!(assigns, :node_settings).web_ui,
        registry_fetch?: summary_type == :containers
      }
    }
  end

  defp metrics(:containers, info) do
    [
      metric("hero-square-3-stack-3d", "Stacks", info.containers.running.stacks_count),
      metric("hero-cube", "Containers", info.containers.running.containers_count),
      metric("hero-square-2-stack", "Images", info.images.combined.images_count)
    ]
  end

  defp metrics(:images, info) do
    [
      metric("hero-square-2-stack", "Images", info.images.combined.images_count),
      metric(
        "hero-circle-stack",
        "Storage",
        Size.human_readable(info.images.combined.total_bytesize)
      )
    ]
  end

  defp metric(icon, label, value, detail \\ "") do
    %{icon: icon, label: label, value: value, detail: detail}
  end

  defp resource_rows(:images, _containers_extended), do: []

  defp resource_rows(:containers, containers_extended) do
    ResourceSummary.rows(containers_extended)
  end

  defp status(:containers, info) do
    counters = info.containers.running.counters

    %{
      visible?: info.containers.running.containers_count > 0,
      items: container_status_items(counters.status)
    }
  end

  defp status(:images, info) do
    %{
      visible?: info.images.combined.images_count > 0,
      items: image_status_items(info.images.combined.counters.status)
    }
  end

  defp container_status_items(status) do
    [
      status_item("Errored", status.errored.count, "bg-error"),
      status_item("Unknown", status.unknown.count, "bg-visual-ignore"),
      status_item("Outdated", status.outdated.count, "bg-visual-warning"),
      status_item("Updated", status.updated.count, "bg-visual-ok")
    ]
  end

  defp image_status_items(status) do
    [
      status_item("Locked", status.locked.count, "bg-visual-ignore"),
      status_item("Unused", status.unused.count, "bg-visual-warning"),
      status_item("In use", status.in_use.count, "bg-visual-ok")
    ]
  end

  defp status_item(label, count, bar_color),
    do: %{label: label, count: count, bar_color: bar_color}

  defp state_icons(:images, _info, _clock_now), do: %{restarting: nil, recently_started: nil}

  defp state_icons(:containers, info, %DateTime{} = clock_now) do
    combined = info.containers.combined

    %{
      restarting: maybe_icon(combined.restarting?, "hero-cog", "text-eye-secondary"),
      recently_started:
        maybe_icon(
          RuntimeState.of(combined.latest_started_at, clock_now) == :just_started,
          "hero-cog",
          "text-warning"
        )
    }
  end

  defp maybe_icon(true, icon, color), do: %{icon: icon, color: color}
  defp maybe_icon(false, _icon, _color), do: nil

  defp staleness(fetch_staleness, since_last_fetch) do
    {icon, color} = staleness_icon(fetch_staleness)

    %{
      icon: icon,
      color: color,
      text: if(is_nil(since_last_fetch), do: nil, else: "#{since_last_fetch} ago")
    }
  end

  defp staleness_icon(:fresh), do: {"hero-clock", "text-success"}
  defp staleness_icon(:stale), do: {"hero-clock", "text-warning"}
  defp staleness_icon(:old), do: {"hero-clock", "text-amber-600"}
  defp staleness_icon(nil), do: {nil, nil}
end
