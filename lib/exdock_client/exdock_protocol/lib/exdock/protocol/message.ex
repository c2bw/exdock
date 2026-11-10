defmodule Exdock.Protocol.Message do
  @moduledoc """
  Constructors and validators for NodeWire map payloads.

  Wire payloads intentionally contain no server-owned structs and no executable
  module/function references. Atom conversion is restricted to this static
  command table after validation.
  """

  alias Exdock.Protocol.Command

  @type command_kind :: String.t()

  @spec command_kinds() :: [command_kind()]
  def command_kinds, do: Command.kinds()

  @spec command(String.t(), atom() | String.t(), list()) :: map()
  def command(id, kind, args) when is_binary(id) and is_list(args) do
    case Command.external(kind) do
      {:ok, kind} ->
        if Command.valid_args?(kind, args) do
          %{"id" => id, "kind" => kind, "args" => args}
        else
          raise ArgumentError, "invalid arguments for agent command: #{inspect(kind)}"
        end

      :error ->
        raise ArgumentError, "unsupported agent command: #{inspect(kind)}"
    end
  end

  @spec valid_command?(term()) :: boolean()
  def valid_command?(payload), do: match?({:ok, _decoded}, Command.decode(payload))

  @spec result(String.t(), command_kind(), String.t(), term(), term()) :: map()
  def result(id, kind, node, data, error)
      when is_binary(id) and is_binary(kind) and is_binary(node) do
    true = Command.valid_kind?(kind)
    %{"id" => id, "kind" => kind, "node" => node, "data" => data, "error" => error}
  end

  @spec valid_result?(term()) :: boolean()
  def valid_result?(%{"id" => id, "kind" => kind, "node" => node, "data" => _data, "error" => _error}),
    do: is_binary(id) and id != "" and Command.valid_kind?(kind) and is_binary(node) and node != ""

  def valid_result?(_payload), do: false

  @spec progress(String.t(), command_kind(), String.t(), term()) :: map()
  def progress(id, kind, node, data)
      when is_binary(id) and is_binary(kind) and is_binary(node) do
    true = Command.valid_kind?(kind)
    %{"id" => id, "kind" => kind, "node" => node, "data" => data}
  end

  @spec valid_progress?(term()) :: boolean()
  def valid_progress?(%{"id" => id, "kind" => kind, "node" => node, "data" => _data}),
    do: is_binary(id) and id != "" and Command.valid_kind?(kind) and is_binary(node) and node != ""

  def valid_progress?(_payload), do: false

  @spec resource_sample(String.t(), String.t(), term()) :: map()
  def resource_sample(node, container_id, sample)
      when is_binary(node) and is_binary(container_id),
      do: %{"node" => node, "container_id" => container_id, "sample" => sample}

  @spec valid_resource_sample?(term()) :: boolean()
  def valid_resource_sample?(%{"node" => node, "container_id" => id, "sample" => _sample}),
    do: is_binary(node) and node != "" and is_binary(id) and id != ""

  def valid_resource_sample?(_payload), do: false
end
