defmodule Exdock.Domain.Container.Configuration do
  @moduledoc """
  Normalized Docker inspect configuration stored with each container snapshot.
  """

  @derive Jason.Encoder
  defstruct [
    :created,
    # inspect.config
    :hostname,
    :env,
    :cmd,
    :healthcheck,
    :image_name_with_id,
    :workingDir,
    :entrypoint,
    :labels,
    # inspect."NetworkSettings"
    :ports,
    :networks,
    # inspect.hostconfig
    :binds,
    :restartpolicy
  ]

  @type t :: %__MODULE__{
          created: String.t(),
          hostname: String.t() | nil,
          env: [String.t()] | nil,
          cmd: [String.t()] | nil,
          healthcheck: map() | nil,
          image_name_with_id: String.t() | nil,
          workingDir: String.t() | nil,
          entrypoint: [String.t()] | nil,
          labels: %{optional(String.t()) => String.t()} | nil,
          ports: %{optional(String.t()) => [map()]} | nil,
          networks: %{optional(String.t()) => map()} | nil,
          binds: [String.t()] | nil,
          restartpolicy: map() | nil
        }

  @spec new(map()) :: t()
  def new(inspect) when is_map(inspect) do
    {config, host_config, image_id, network_settings} = inspect_parts(inspect)

    %__MODULE__{
      created: docker_field(inspect, :Created),
      hostname: docker_field(config, :Hostname),
      env: config |> docker_field(:Env) |> list_or_empty(),
      cmd: docker_field(config, :Cmd),
      healthcheck: config |> docker_field(:Healthcheck) |> json_safe(),
      image_name_with_id: image_name_with_id(docker_field(config, :Image), image_id),
      workingDir: docker_field(config, :WorkingDir),
      entrypoint: docker_field(config, :Entrypoint),
      labels: docker_field(config, :Labels),
      ports: network_settings |> docker_field(:Ports) |> map_or_empty() |> json_safe(),
      networks: network_settings |> docker_field(:Networks) |> map_or_empty() |> json_safe(),
      binds: host_config |> docker_field(:Binds) |> list_or_empty(),
      restartpolicy: host_config |> docker_field(:RestartPolicy) |> json_safe()
    }
  end

  @doc """
  Count the number of network port bindings in the container configuration.
  """
  @spec port_binds_count(t()) :: integer()
  def port_binds_count(%__MODULE__{ports: ports}),
    do: ports |> map_or_empty() |> Enum.count(&host_binding_present?/1)

  @doc """
  Check if the container has a network host bind.
  """
  @spec has_network_host_bind(t()) :: boolean()
  def has_network_host_bind(%__MODULE__{networks: networks}),
    do: networks |> map_or_empty() |> Map.has_key?("host")

  defp inspect_parts(%{
         "Config" => config,
         "HostConfig" => host_config,
         "Image" => image_id,
         "NetworkSettings" => network_settings
       })
       when is_map(config) and is_map(host_config) and is_map(network_settings) do
    {config, host_config, image_id, network_settings}
  end

  defp docker_field(map, field), do: Map.get(map, Atom.to_string(field))

  defp host_binding_present?({_container_port, nil}), do: false
  defp host_binding_present?({_container_port, _host_bindings}), do: true

  defp image_name_with_id(nil, _image_id), do: ""
  defp image_name_with_id(_image_name, nil), do: ""
  defp image_name_with_id(image_name, image_id), do: image_name <> "@" <> image_id

  defp list_or_empty(nil), do: []
  defp list_or_empty(list) when is_list(list), do: list

  defp map_or_empty(nil), do: %{}
  defp map_or_empty(map) when is_map(map), do: map

  defp json_safe(value), do: value
end
