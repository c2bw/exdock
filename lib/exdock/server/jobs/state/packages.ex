defmodule Exdock.Server.Jobs.State.Packages do
  @moduledoc """
  Tracks package jobs that group multiple details under one visible operation.

  Packages let the UI show aggregate progress for bulk operations while each
  detail still executes and reports through the normal job pipeline.
  """

  alias Exdock.Server.Jobs

  defstruct [
    :packages
  ]

  @type t :: %__MODULE__{
          packages: %{String.t() => Jobs.Package.t()}
        }

  @spec new() :: t()
  def new() do
    %__MODULE__{packages: %{}}
  end

  @spec add(t(), Jobs.Package.t()) :: t()
  def add(%__MODULE__{} = state, %Jobs.Package{} = package), do: put_package(state, package)

  @spec remove(t(), Jobs.Package.t()) :: t()
  def remove(%__MODULE__{} = state, %Jobs.Package{id: id}), do: remove_package(state, id)

  @type effect :: {:package_result, String.t(), term()}

  @spec result(t(), Jobs.Result.t()) :: {t(), [effect()]}
  def result(%__MODULE__{packages: packages} = state, %Jobs.Result{id: detail_id, error: error}) when is_binary(detail_id) do
    # Offer each detail result to every waiting package. A single detail can
    # belong to more than one aggregate operation.
    {state, effect_chunks} =
      Enum.reduce(packages, {state, []}, fn
        {_id, package}, {current_state, effect_chunks} ->
          {current_state, package_effects} =
            reconcile_package_detail_result(current_state, package, detail_id, error)

          {current_state, [package_effects | effect_chunks]}
      end)

    effects =
      effect_chunks
      |> Enum.reverse()
      |> List.flatten()

    {state, effects}
  end

  defp reconcile_package_detail_result(%__MODULE__{} = state, %Jobs.Package{} = package, detail_id, error) do
    case Jobs.Package.result(package, detail_id, error) do
      :detail_unknown ->
        {state, []}

      {:awaiting_more_results, package} ->
        {put_package(state, package), []}

      {:aggregate_complete, package_error} ->
        {remove_package(state, package.id), [{:package_result, package.id, package_error}]}
    end
  end

  defp put_package(%__MODULE__{packages: packages} = state, %Jobs.Package{id: id} = package) do
    %{state | packages: Map.put(packages, id, package)}
  end

  defp remove_package(%__MODULE__{packages: packages} = state, id) do
    %{state | packages: Map.delete(packages, id)}
  end
end
