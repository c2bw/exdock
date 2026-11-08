defmodule Exdock.ClientLib.Container.Recreator.Plan do
  @moduledoc """
  Immutable recreation plan derived from a Docker inspect response.

  The plan normalizes the original container identity and configuration before
  any destructive Docker operation begins.
  """

  alias DockerEngineAPI.Model

  defstruct [
    :original_inspect,
    :original_id,
    :original_name,
    :temporary_name,
    :original_running,
    :original_networks,
    :image_tag,
    :create_request
  ]

  @type t :: %__MODULE__{
          original_inspect: Model.ContainerInspectResponse.t(),
          original_id: String.t(),
          original_name: String.t(),
          temporary_name: String.t(),
          original_running: boolean(),
          original_networks: map(),
          image_tag: String.t(),
          create_request: Model.ContainerCreateRequest.t()
        }

  @spec build(term()) :: {:ok, t()} | {:error, :malformed_response | :auto_remove_unsupported}
  def build(%Model.ContainerInspectResponse{HostConfig: %{AutoRemove: true}}),
    do: {:error, :auto_remove_unsupported}

  def build(
        %Model.ContainerInspectResponse{
          Id: id,
          Config: %Model.ContainerConfig{Image: image_tag},
          State: %Model.ContainerState{Status: status},
          NetworkSettings: %Model.NetworkSettings{Networks: networks},
          Name: name
        } = inspect
      )
      when is_binary(id) and is_binary(image_tag) and is_map(networks) and
             is_binary(name) do
    original_name = String.replace_prefix(name, "/", "")

    {:ok,
     %__MODULE__{
       original_inspect: inspect,
       original_id: id,
       original_name: original_name,
       temporary_name: temporary_name(original_name, id),
       original_running: status == "running",
       original_networks: networks,
       image_tag: normalize_image_tag(image_tag),
       create_request: create_request(inspect)
     }}
  end

  def build(_inspect), do: {:error, :malformed_response}

  defp normalize_image_tag(image_reference) do
    image_reference
    |> String.replace_prefix("docker.io/library/", "")
    |> then(fn reference ->
      if tagged_or_digested?(reference), do: reference, else: "#{reference}:latest"
    end)
  end

  defp tagged_or_digested?(reference) do
    String.contains?(reference, "@") or
      reference
      |> String.split("/")
      |> List.last()
      |> String.contains?(":")
  end

  defp temporary_name(name, id), do: "#{name}-exdock-old-#{String.slice(id, 0, 12)}"

  defp preserve_volumes(%Model.ContainerInspectResponse{HostConfig: host, Mounts: mounts}) do
    host = host || %Model.HostConfig{}
    configured_mounts = host."Mounts" || []

    {configured_mounts, pinned} =
      Enum.reduce(mounts || [], {configured_mounts, []}, fn
        %{Type: "volume", Name: name, Destination: destination, RW: writable}, {configured, pinned}
        when is_binary(name) and is_binary(destination) ->
          case Enum.find(configured, &(&1."Target" == destination)) do
            %{Type: "volume", Source: source} when source in [nil, ""] ->
              updated =
                Enum.map(configured, fn mount ->
                  if mount."Target" == destination, do: %{mount | Source: name}, else: mount
                end)

              {updated, pinned}

            nil ->
              # Explicit binds already preserve their source. Destination-only
              # binds request a new anonymous volume and must be replaced.
              binds = host."Binds" || []
              explicit? = Enum.any?(binds, &explicit_bind?(&1, destination))

              if explicit? do
                {configured, pinned}
              else
                mount = %Model.Mount{Type: "volume", Source: name, Target: destination, ReadOnly: writable == false}
                {configured, [mount | pinned]}
              end

            _explicit_mount ->
              {configured, pinned}
          end

        _mount, acc ->
          acc
      end)

    pinned_destinations = Enum.map(pinned, & &1."Target")

    binds =
      Enum.reject(host."Binds" || [], fn bind ->
        Enum.any?(pinned_destinations, fn destination ->
          anonymous_bind?(bind, destination)
        end)
      end)

    %{host | Mounts: configured_mounts ++ Enum.reverse(pinned), Binds: binds}
  end

  defp explicit_bind?(bind, destination) do
    case String.split(bind, ":") do
      [source, ^destination] -> source != ""
      [source, ^destination, _options] -> source != ""
      _ -> false
    end
  end

  defp anonymous_bind?(bind, destination) do
    case String.split(bind, ":") do
      [^destination] -> true
      [^destination, options] -> not String.starts_with?(options, "/")
      _ -> false
    end
  end

  defp create_request(
         %Model.ContainerInspectResponse{
           Config: %Model.ContainerConfig{} = config
         } = configuration
       ) do
    %Model.ContainerCreateRequest{
      Hostname: config."Hostname",
      Domainname: config."Domainname",
      User: config."User",
      AttachStdin: config."AttachStdin",
      AttachStdout: config."AttachStdout",
      AttachStderr: config."AttachStderr",
      ExposedPorts: config."ExposedPorts",
      Tty: config."Tty",
      OpenStdin: config."OpenStdin",
      StdinOnce: config."StdinOnce",
      Env: config."Env",
      Cmd: config."Cmd",
      Healthcheck: config."Healthcheck",
      ArgsEscaped: config."ArgsEscaped",
      Image: config."Image",
      Volumes: config."Volumes",
      WorkingDir: config."WorkingDir",
      Entrypoint: config."Entrypoint",
      NetworkDisabled: config."NetworkDisabled",
      OnBuild: config."OnBuild",
      Labels: config."Labels",
      StopSignal: config."StopSignal",
      StopTimeout: config."StopTimeout",
      Shell: config."Shell",
      HostConfig: preserve_volumes(configuration),
      NetworkingConfig: nil
    }
  end
end
