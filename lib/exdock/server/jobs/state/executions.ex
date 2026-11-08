defmodule Exdock.Server.Jobs.State.Executions do
  @moduledoc "Tracks execution IDs and aggregates multi-spec detail completion."

  alias Exdock.Server.Jobs

  defstruct parents: %{}, groups: %{}

  @type t :: %__MODULE__{parents: map(), groups: map()}

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec add(t(), Jobs.Detail.t()) :: t()
  def add(state, %Jobs.Detail{spec_list: [_single]}), do: state

  def add(%__MODULE__{} = state, %Jobs.Detail{id: id, spec_list: specs} = detail) do
    ids = Enum.map(specs, &elem(&1, 1))
    {spec, _id} = hd(specs)
    info = detail |> Jobs.Job.new(spec) |> Jobs.Info.new()
    group = %{pending: MapSet.new(ids), failure: nil, info: info}

    %{
      state
      | parents: Enum.reduce(ids, state.parents, &Map.put(&2, &1, id)),
        groups: Map.put(state.groups, id, group)
    }
  end

  @spec info(t(), String.t()) :: Jobs.Info.t() | nil
  def info(%__MODULE__{groups: groups}, id) do
    case Map.get(groups, id) do
      nil -> nil
      group -> group.info
    end
  end

  @spec complete(t(), Jobs.Result.t()) :: {t(), nil | {Jobs.Info.t(), Jobs.Result.t()}}
  def complete(%__MODULE__{} = state, %Jobs.Result{id: id} = result) do
    case Map.pop(state.parents, id) do
      {nil, _parents} ->
        {state, nil}

      {parent, parents} ->
        group = Map.fetch!(state.groups, parent)
        pending = MapSet.delete(group.pending, id)
        failure = group.failure || if(result.error != nil, do: result)
        state = %{state | parents: parents}

        if MapSet.size(pending) == 0 do
          state = %{state | groups: Map.delete(state.groups, parent)}
          {state, {group.info, %{(failure || result) | id: parent}}}
        else
          group = %{group | pending: pending, failure: failure}
          {%{state | groups: Map.put(state.groups, parent, group)}, nil}
        end
    end
  end
end
