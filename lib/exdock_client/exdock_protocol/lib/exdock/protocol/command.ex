defmodule Exdock.Protocol.Command do
  @moduledoc """
  Canonical catalog and decoder for commands accepted by the agent.

  Successful decoding returns a command-specific struct, preserving the
  relationship between command identity and its validated fields.
  """

  alias Exdock.Protocol.Command.{
    ContainerLogs,
    ContainerRecreate,
    ContainerResources,
    ContainerRestart,
    ContainerStart,
    ContainerStop,
    ImageDelete,
    ImagePull,
    NodeRefresh
  }

  @commands %{
    "node_refresh" => :node_refresh,
    "container_recreate" => :container_recreate,
    "image_delete" => :image_delete,
    "image_pull" => :image_pull,
    "container_start" => :container_start,
    "container_stop" => :container_stop,
    "container_restart" => :container_restart,
    "container_logs" => :container_logs,
    "container_resources" => :container_resources
  }

  @type kind ::
          :node_refresh
          | :container_recreate
          | :image_delete
          | :image_pull
          | :container_start
          | :container_stop
          | :container_restart
          | :container_logs
          | :container_resources

  @type decoded ::
          NodeRefresh.t()
          | ContainerRecreate.t()
          | ImageDelete.t()
          | ImagePull.t()
          | ContainerStart.t()
          | ContainerStop.t()
          | ContainerRestart.t()
          | ContainerLogs.t()
          | ContainerResources.t()

  @spec kinds() :: [String.t()]
  def kinds, do: Map.keys(@commands)

  @spec valid_kind?(term()) :: boolean()
  def valid_kind?(kind) when is_binary(kind), do: Map.has_key?(@commands, kind)
  def valid_kind?(kind) when is_atom(kind), do: kind in Map.values(@commands)
  def valid_kind?(_kind), do: false

  @spec external(kind() | String.t()) :: {:ok, String.t()} | :error
  def external(kind) when is_atom(kind) do
    Enum.find_value(@commands, :error, fn
      {external, ^kind} -> {:ok, external}
      _entry -> false
    end)
  end

  def external(kind) when is_binary(kind) do
    if valid_kind?(kind), do: {:ok, kind}, else: :error
  end

  def external(_kind), do: :error

  @spec internal(String.t()) :: {:ok, kind()} | :error
  def internal(kind) when is_binary(kind), do: Map.fetch(@commands, kind)
  def internal(_kind), do: :error

  @spec valid_args?(String.t() | kind(), term()) :: boolean()
  def valid_args?(kind, args) do
    with {:ok, internal_kind} <- normalize_kind(kind) do
      match?({:ok, _decoded}, decode_arguments(internal_kind, "validation", args))
    else
      :error -> false
    end
  end

  @spec decode(term()) :: {:ok, decoded()} | {:error, term()}
  def decode(%{"id" => id, "kind" => external_kind, "args" => args}) do
    with :ok <- validate_id(id),
         {:ok, kind} <- decode_kind(external_kind) do
      case decode_arguments(kind, id, args) do
        {:ok, decoded} -> {:ok, decoded}
        :error -> {:error, {:invalid_command_arguments, external_kind}}
      end
    end
  end

  def decode(%{"kind" => kind}), do: {:error, {:invalid_command_arguments, kind}}
  def decode(_payload), do: {:error, {:invalid_command, :malformed_payload}}

  defp validate_id(id) when is_binary(id) and id != "", do: :ok
  defp validate_id(id), do: {:error, {:invalid_command_id, id}}

  defp decode_kind(kind) do
    case internal(kind) do
      {:ok, internal_kind} -> {:ok, internal_kind}
      :error -> {:error, {:unsupported_command, kind}}
    end
  end

  defp normalize_kind(kind) when is_atom(kind), do: if(valid_kind?(kind), do: {:ok, kind}, else: :error)
  defp normalize_kind(kind) when is_binary(kind), do: internal(kind)
  defp normalize_kind(_kind), do: :error

  defp decode_arguments(:node_refresh, id, [%{"retrieve_resources" => value}])
       when is_boolean(value),
       do: {:ok, %NodeRefresh{id: id, retrieve_resources: value}}

  defp decode_arguments(:container_recreate, id, [container_id, pull_image])
       when is_binary(container_id) and container_id != "" and is_boolean(pull_image),
       do: {:ok, %ContainerRecreate{id: id, container_id: container_id, pull_image: pull_image}}

  defp decode_arguments(:container_logs, id, [container_id])
       when is_binary(container_id) and container_id != "",
       do: {:ok, %ContainerLogs{id: id, container_id: container_id, opts: []}}

  defp decode_arguments(:container_logs, id, [container_id, opts])
       when is_binary(container_id) and container_id != "" and is_list(opts),
       do: {:ok, %ContainerLogs{id: id, container_id: container_id, opts: opts}}

  defp decode_arguments(:image_delete, id, [identifier])
       when is_binary(identifier) and identifier != "",
       do: {:ok, %ImageDelete{id: id, image_id: identifier}}

  defp decode_arguments(:image_pull, id, [identifier])
       when is_binary(identifier) and identifier != "",
       do: {:ok, %ImagePull{id: id, image_tag: identifier}}

  defp decode_arguments(:container_start, id, [identifier])
       when is_binary(identifier) and identifier != "",
       do: {:ok, %ContainerStart{id: id, container_id: identifier}}

  defp decode_arguments(:container_stop, id, [identifier])
       when is_binary(identifier) and identifier != "",
       do: {:ok, %ContainerStop{id: id, container_id: identifier}}

  defp decode_arguments(:container_restart, id, [identifier])
       when is_binary(identifier) and identifier != "",
       do: {:ok, %ContainerRestart{id: id, container_id: identifier}}

  defp decode_arguments(:container_resources, id, [identifier])
       when is_binary(identifier) and identifier != "",
       do: {:ok, %ContainerResources{id: id, container_id: identifier}}

  defp decode_arguments(_kind, _id, _args), do: :error
end
