defmodule ExdockWeb.ContainersLive.ContainerListRow.ViewModel do
  @moduledoc """
  Derives the formatted state consumed by a container table row.

  Keeping this work outside the component makes rendering declarative and
  gives the presentation policy a focused test surface.
  """

  alias Exdock.{Datetime, Size}
  alias Exdock.ReadModel.Container
  alias Exdock.ReadModel.Container.{Core, Extended}
  alias ExdockWeb.Format
  alias ExdockWeb.Presentation.Container, as: ContainerPresentation

  defstruct [
    :priority,
    :priority_class,
    :name,
    :stack_name,
    :image_tag,
    :image_url,
    :image_size,
    :pull_state,
    :build,
    :resources,
    :duration,
    :lifecycle,
    :network,
    error?: false
  ]

  @type t :: %__MODULE__{}
  @type input :: %{
          required(:name) => String.t(),
          required(:core) => Core.t(),
          required(:extended) => Extended.t(),
          required(:is_outdated) => boolean(),
          required(:is_running) => boolean(),
          optional(atom()) => term()
        }

  @spec build(input()) :: t()
  def build(%{
        name: name,
        core: %Core{} = core,
        extended: %Extended{} = extended,
        is_outdated: outdated?,
        is_running: running?,
        clock_now: %DateTime{} = clock_now
      }) do
    %__MODULE__{
      priority: core.settings.priority,
      priority_class: ContainerPresentation.priority_class(core.settings.priority),
      name: ContainerPresentation.container_name(name),
      stack_name: ContainerPresentation.stack_name(core.stack_name),
      image_tag: ContainerPresentation.image_tag(core.image_tag),
      image_url: core.image_url,
      image_size: core.image_size_human,
      pull_state: pull_state(outdated?, core.image_present_on_node),
      build: build_date(outdated?, core.image_build_date, core.remote_image_date),
      resources: resources(running?, extended.resources),
      duration: duration(core, running?, clock_now),
      lifecycle: lifecycle(core, running?, clock_now),
      network: network(core),
      error?: core.image_status not in [:unknown, :outdated, :updated]
    }
  end

  defp pull_state(false, _present?), do: nil
  defp pull_state(true, true), do: :present
  defp pull_state(true, _present?), do: :available

  defp build_date(false, local, _remote) do
    %{mode: :current, local: ContainerPresentation.build_date_iso8601(local)}
  end

  defp build_date(true, local, remote) do
    remote_available? =
      match?(%DateTime{}, remote) and ContainerPresentation.remote_build_available?(remote)

    %{
      mode: :comparison,
      local: DateTime.to_date(local),
      remote: if(remote_available?, do: DateTime.to_date(remote)),
      age_days: if(remote_available?, do: ContainerPresentation.build_age_days(local, remote))
    }
  end

  defp resources(false, _resources), do: []

  defp resources(true, resources) do
    [
      metric("CPU", Format.percentage(resources.rates.cpu_usage), "hero-cpu-chip"),
      metric(
        "Memory",
        Size.human_readable(resources.rates.used_memory, decimals: 1),
        "hero-chart-bar-square"
      ),
      metric(
        "I/O",
        resources
        |> Container.resource_aggregate(:io)
        |> Size.human_readable(
          decimals: 1,
          truncate_zero_decimals: true,
          time_unit: "/s"
        ),
        "hero-server"
      ),
      metric(
        "Network",
        resources
        |> Container.resource_aggregate(:net)
        |> Size.human_readable(
          decimals: 1,
          truncate_zero_decimals: true,
          time_unit: "/s"
        ),
        "hero-wifi"
      )
    ]
  end

  defp metric(label, value, icon), do: %{label: label, value: value, icon: icon}

  defp duration(core, running?, clock_now) do
    change_at = if running?, do: core.state.started_at, else: core.state.finished_at

    change_at
    |> Datetime.maybe_datetime!()
    |> ContainerPresentation.running_time(clock_now)
  end

  defp lifecycle(core, true, clock_now) do
    case Container.runtime_state(core, clock_now) do
      :just_started -> %{title: "Starting", color: "text-warning"}
      :running -> %{title: "Running", color: "text-success"}
      nil -> nil
    end
  end

  defp lifecycle(%{state: %{restarting: true}}, false, _clock_now) do
    %{title: "Restarting", color: "text-eye-secondary"}
  end

  defp lifecycle(_core, false, _clock_now), do: %{title: "Stopped", color: "text-high-visibility"}

  defp network(core) do
    cond do
      Container.host_network?(core) -> :host
      Container.published_port_count(core) > 0 -> :published
      true -> nil
    end
  end
end
