defmodule Exdock.Server.Jobs.Package do
  @moduledoc """
  Groups multiple job details into one aggregate operation.

  Packages are useful for bulk image pulls, deletes, and container recreates.
  Each detail still reports independently, while the package emits one final
  success or failure result for status/logging.
  """

  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.Payload

  defstruct [
    :id,
    :name,
    :details,
    :log_on_start
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          name: atom(),
          details: [Jobs.Detail.t()],
          log_on_start: Payload.package_log() | nil
        }

  @type transition ::
          :detail_unknown
          | {:awaiting_more_results, t()}
          | {:aggregate_complete, Payload.error()}

  @spec new(atom(), list(Jobs.Detail.t()), Payload.package_log() | nil) :: t()
  def new(name, details, log_on_start) do
    unless all_details?(details) do
      raise ArgumentError, "details must be a list of Jobs.Detail"
    end

    %__MODULE__{
      id: Jobs.Helper.generate_id(),
      name: name,
      details: details,
      log_on_start: log_on_start
    }
  end

  @spec result(t(), String.t(), Payload.error()) :: transition()
  def result(%__MODULE__{details: details} = package, id, error) when is_binary(id) do
    if detail_id?(details, id) do
      known_detail_result(package, id, error)
    else
      :detail_unknown
    end
  end

  defp all_details?(details) do
    Enum.all?(details, &match?(%Jobs.Detail{}, &1))
  end

  defp detail_id?(details, detail_id),
    do: Enum.any?(details, &match?(%Jobs.Detail{id: ^detail_id}, &1))

  # A package fails fast as soon as any detail fails.
  defp known_detail_result(_package, _detail_id, error) when not is_nil(error),
    do: {:aggregate_complete, error}

  defp known_detail_result(%__MODULE__{} = package, detail_id, nil) do
    # Successful details are removed from the pending set until the aggregate
    # can emit its single final success result.
    case pending_details_after_success(package, detail_id) do
      [] -> {:aggregate_complete, nil}
      details -> {:awaiting_more_results, %{package | details: details}}
    end
  end

  defp pending_details_after_success(%__MODULE__{details: details}, detail_id) do
    Enum.reject(details, &match?(%Jobs.Detail{id: ^detail_id}, &1))
  end

  @spec set_automated(t()) :: t()
  def set_automated(%__MODULE__{details: details} = package) do
    %{package | details: Enum.map(details, &Jobs.Detail.set_automated/1)}
  end
end
