defmodule Exdock.Server.State.ContainerStatus do
  @moduledoc """
  Computes visible container-status transitions without performing side effects.

  Container structures stay as pure data transformations; state orchestration
  compares the before/after snapshots and emits transition effects separately.
  """

  alias Exdock.Server.State
  alias Exdock.Server.State.Storage
  alias Exdock.Domain.Container
  alias Exdock.Domain.Container.Core
  alias Exdock.Domain.Container.Core.ImageData
  alias Exdock.Domain.Container.Settings

  @type transition :: %{
          node: String.t(),
          name: String.t(),
          priority: integer(),
          previous: atom() | nil,
          current: atom(),
          notify?: boolean()
        }

  @spec transitions(State.t(), State.t()) :: [transition()]
  def transitions(%State{} = before_state, %State{} = after_state) do
    before_by_node = Storage.Containers.full_string_map(before_state)
    after_by_node = Storage.Containers.full_string_map(after_state)

    Enum.flat_map(after_by_node, fn {node, containers} ->
      between(node, Map.get(before_by_node, node, []), containers)
    end)
  end

  @doc false
  @spec between(String.t(), [Container.t()], [Container.t()]) :: [transition()]
  def between(node, before_containers, after_containers)
      when is_binary(node) and is_list(before_containers) and is_list(after_containers) do
    before_by_name = Map.new(before_containers, &{&1.name, &1})

    after_containers
    |> Enum.flat_map(&transition_for(node, &1, Map.get(before_by_name, &1.name)))
  end

  defp transition_for(
         node,
         %Container{
           name: name,
           core: %Core{
             is_running: running?,
             image_data: %ImageData{status: current},
             settings: %Settings{priority: priority}
           }
         },
         previous
       )
       when is_binary(node) and is_binary(name) and is_boolean(running?) and is_atom(current) and
              is_integer(priority) do
    previous_status = status(previous)

    cond do
      is_nil(previous) and not running? ->
        []

      previous_status == current ->
        []

      true ->
        [
          %{
            node: node,
            name: name,
            priority: priority,
            previous: previous_status,
            current: current,
            notify?: not is_nil(previous)
          }
        ]
    end
  end

  defp status(nil), do: nil
  defp status(%Container{core: %Core{image_data: %ImageData{status: status}}}), do: status
end
