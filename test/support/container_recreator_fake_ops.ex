defmodule Exdock.ContainerRecreatorFakeOps do
  @moduledoc false

  def inspect(agent, id) do
    operation(agent, {:inspect, id}, fn state ->
      inspect =
        if id == "new-id" do
          if state.replacement.running do
            %{state.new_inspect | State: Map.get(state, :ready_state, %{Status: "running", Health: %{Status: "healthy"}})}
          else
            state.new_inspect
          end
        else
          state.original_inspect
        end

      {{:ok, inspect}, state}
    end)
  end

  def inspect_image(agent, reference) do
    operation(agent, {:inspect_image, reference}, fn state ->
      references = state.image_tags ++ Map.get(state, :image_digests, []) ++ List.wrap(Map.get(state, :image_id))
      normalized = String.replace_prefix(reference, "docker.io/library/", "")

      response =
        if normalized in references or "#{normalized}:latest" in references,
          do: {:ok, %{Id: Map.get(state, :image_id, "image-id")}},
          else: {:error, %Tesla.Env{status: 404}}

      {Map.get(state, :image_response, response), state}
    end)
  end

  def stop(agent, id) do
    operation(agent, {:stop, id}, fn state ->
      state =
        case id do
          "original-id" -> put_in(state.original.running, false)
          "new-id" -> put_in(state.replacement.running, false)
        end

      {{:ok, %{}}, state}
    end)
  end

  def rename(agent, "original-id", name) do
    operation(agent, {:rename, "original-id", name}, fn state ->
      {{:ok, %{}}, put_in(state.original.name, name)}
    end)
  end

  def create(agent, name, request) do
    operation(agent, :create, fn state ->
      replacement = %{name: name, running: false, networks: MapSet.new(["bridge"])}
      {{:ok, %{Id: "new-id"}}, state |> Map.put(:replacement, replacement) |> Map.put(:create_request, request)}
    end)
  end

  def start(agent, id) do
    operation(agent, {:start, id}, fn state ->
      state =
        case id do
          "original-id" -> put_in(state.original.running, true)
          "new-id" -> put_in(state.replacement.running, true)
        end

      {{:ok, %{}}, state}
    end)
  end

  def delete(agent, id) do
    operation(agent, {:delete, id}, fn state ->
      state =
        case id do
          "original-id" -> %{state | original: nil}
          "new-id" -> %{state | replacement: nil}
        end

      {{:ok, %{}}, state}
    end)
  end

  def disconnect(agent, network, request) do
    container = request."Container"

    operation(agent, {:disconnect, container, network}, fn state ->
      state =
        case container do
          "original-id" -> update_in(state.original.networks, &MapSet.delete(&1, network))
          "new-id" -> update_in(state.replacement.networks, &MapSet.delete(&1, network))
        end

      {{:ok, %{}}, state}
    end)
  end

  def connect(agent, network, request) do
    container = request."Container"

    operation(agent, {:connect, container, network}, fn state ->
      state =
        case container do
          "original-id" -> update_in(state.original.networks, &MapSet.put(&1, network))
          "new-id" -> update_in(state.replacement.networks, &MapSet.put(&1, network))
        end

      {{:ok, %{}}, state}
    end)
  end

  defp operation(agent, key, success) do
    response =
      Agent.get_and_update(agent, fn state ->
        state = update_in(state.calls, &[key | &1])

        if state.fail_at == key do
          {{:error, :injected_failure}, state}
        else
          success.(state)
        end
      end)

    if response == {:error, :injected_failure} do
      case Agent.get(agent, &Map.get(&1, :failure_mode)) do
        :raise -> raise "injected exception"
        :exit -> exit(:injected_exit)
        _ -> response
      end
    else
      response
    end
  end
end
