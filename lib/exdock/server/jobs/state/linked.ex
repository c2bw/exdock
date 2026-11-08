defmodule Exdock.Server.Jobs.State.Linked do
  @moduledoc """
  Tracks duplicate job ids linked to the running job that will satisfy them.

  When the gatekeeper coalesces equivalent remote work, the duplicate job id is
  linked under the already-running job id. When the running job finishes, its
  result is propagated to every duplicate id.
  """

  defstruct [
    :linked
  ]

  @empty_duplicate_ids MapSet.new()

  @type t :: %__MODULE__{
          linked: %{String.t() => MapSet.t(String.t())}
        }

  @spec new() :: t()
  def new() do
    %__MODULE__{linked: %{}}
  end

  @doc """
  Link a duplicate job id to the running job id that owns the work.
  """
  @spec add(t(), String.t(), String.t() | nil) :: t()
  def add(%__MODULE__{} = state, _duplicate_id, nil), do: state

  def add(%__MODULE__{linked: linked} = state, duplicate_id, running_id)
      when is_binary(duplicate_id) and is_binary(running_id) do
    %{state | linked: link_duplicate_id(linked, running_id, duplicate_id)}
  end

  @doc """
  Get duplicate job ids that should receive the result for a running id.
  """
  @spec get_linked(t(), String.t()) :: [String.t()]
  def get_linked(%__MODULE__{linked: linked}, running_id) when is_binary(running_id) do
    linked
    |> duplicate_ids_for_running_id(running_id)
    |> MapSet.to_list()
  end

  @doc """
  Remove links pointing at a completed running id.
  """
  @spec remove_link(t(), String.t()) :: t()
  def remove_link(%__MODULE__{linked: linked} = state, running_id) when is_binary(running_id) do
    %{state | linked: Map.delete(linked, running_id)}
  end

  defp link_duplicate_id(linked, running_id, duplicate_id) do
    Map.update(linked, running_id, MapSet.new([duplicate_id]), &MapSet.put(&1, duplicate_id))
  end

  defp duplicate_ids_for_running_id(linked, running_id) do
    Map.get(linked, running_id, @empty_duplicate_ids)
  end
end
