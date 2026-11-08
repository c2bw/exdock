defmodule Exdock.ReadModel.Container do
  @moduledoc """
  Public container projection consumed by delivery layers.

  Runtime storage owns the domain representation. This struct keeps the stable
  identity and presentation fields exposed to LiveViews while helper functions
  hide storage-specific modules used to calculate derived values.
  """

  alias Exdock.Container.{Policy, RuntimeState}
  alias Exdock.ReadModel.Container.{Core, Extended, Key}

  defstruct [:node, :name, :id, :core, :extended]

  @type core :: Core.t()
  @type extended :: Extended.t()
  @type t :: %__MODULE__{
          node: String.t(),
          name: String.t(),
          id: String.t(),
          core: core(),
          extended: extended()
        }

  @spec from_domain(map() | t()) :: t()
  def from_domain(%__MODULE__{} = container), do: container

  def from_domain(%{node: node, name: name, id: id, core: core, extended: extended}) do
    %__MODULE__{
      node: node,
      name: name,
      id: id,
      core: Core.from_domain(core),
      extended: Extended.from_domain(extended)
    }
  end

  @spec priority(t()) :: integer()
  def priority(%__MODULE__{core: %{settings: %{priority: priority}}}), do: priority

  @spec settings(t()) :: map()
  def settings(%__MODULE__{core: %{settings: settings}}), do: settings

  @spec image_status(t()) :: atom()
  def image_status(%__MODULE__{core: %{image_status: status}}), do: status

  @spec running?(t()) :: boolean()
  def running?(%__MODULE__{core: %{is_running: running?}}), do: running?

  @spec restarting?(t()) :: boolean()
  def restarting?(%__MODULE__{core: %{state: %{restarting: restarting?}}}), do: restarting? == true

  @spec runtime_state(core(), DateTime.t()) :: :just_started | :running | nil
  def runtime_state(%{state: %{started_at: started_at}}, %DateTime{} = now),
    do: RuntimeState.of(started_at, now)

  @spec host_network?(core()) :: boolean()
  def host_network?(%{configuration: configuration}) do
    configuration
    |> Map.get(:networks, %{})
    |> Kernel.||(%{})
    |> Map.has_key?("host")
  end

  @spec published_port_count(core()) :: non_neg_integer()
  def published_port_count(%{configuration: configuration}) do
    configuration
    |> Map.get(:ports, %{})
    |> Kernel.||(%{})
    |> Enum.count(fn {_container_port, host_bindings} -> host_bindings != nil end)
  end

  @spec empty_extended() :: extended()
  def empty_extended, do: Extended.empty()

  @spec key(t() | map()) :: Key.t()
  def key(container), do: Key.from_container(container)

  @spec resource_aggregate(map() | nil, :io | :net) :: number() | nil
  def resource_aggregate(nil, _type), do: nil

  def resource_aggregate(%{rates: rates}, type) when type in [:io, :net] do
    keys = if type == :io, do: [:read, :write], else: [:rx, :tx]
    rate_group = Map.get(rates, type, %{})
    values = Enum.map(keys, &Map.get(rate_group, &1))
    if Enum.all?(values, &is_number/1), do: Enum.sum(values), else: nil
  end

  @spec empty_resources() :: map()
  defdelegate empty_resources(), to: Extended

  @spec latest_resources(map()) :: map() | nil
  def latest_resources(%{records: [latest | _]}), do: latest
  def latest_resources(%{records: []}), do: nil

  @spec valid_priority?(term()) :: boolean()
  defdelegate valid_priority?(priority), to: Policy
end
