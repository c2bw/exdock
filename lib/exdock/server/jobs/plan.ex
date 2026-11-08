defmodule Exdock.Server.Jobs.Plan do
  @moduledoc """
  Normalized work produced by runtime commands before it reaches the dispatcher.

  A plan records whether details are independent or belong to an existing
  package. Operation correlation and automation are plan transformations, so
  callers never have to reinterpret raw detail lists themselves.
  """

  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.Payload

  @enforce_keys [:details]
  defstruct details: [],
            package_name: nil,
            package_id: nil,
            package_log_on_start: nil,
            packaged?: false,
            operation_id: nil,
            automated?: false

  @type source :: Jobs.Detail.t() | Jobs.Package.t() | [Jobs.Detail.t()] | nil
  @type submission ::
          :empty
          | {:one, Jobs.Detail.t() | Jobs.Package.t()}
          | {:batch, [Jobs.Detail.t()]}
          | {:individual, [Jobs.Detail.t()]}

  @type t :: %__MODULE__{
          details: [Jobs.Detail.t()],
          package_name: atom() | nil,
          package_id: String.t() | nil,
          package_log_on_start: Payload.package_log() | nil,
          packaged?: boolean(),
          operation_id: Ecto.UUID.t() | nil,
          automated?: boolean()
        }

  @spec new(source()) :: t()
  def new(nil), do: %__MODULE__{details: []}
  def new([]), do: %__MODULE__{details: []}
  def new(%Jobs.Detail{} = detail), do: %__MODULE__{details: [detail]}

  def new([%Jobs.Detail{} | _] = details) do
    if Enum.all?(details, &match?(%Jobs.Detail{}, &1)) do
      %__MODULE__{details: details}
    else
      raise ArgumentError, "job plan details must all be Jobs.Detail structs"
    end
  end

  def new(%Jobs.Package{} = package) do
    %__MODULE__{
      details: package.details,
      package_name: package.name,
      package_id: package.id,
      package_log_on_start: package.log_on_start,
      packaged?: true
    }
  end

  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{details: details}), do: details == []

  @spec attach_operation(t(), Ecto.UUID.t() | nil) :: t()
  def attach_operation(%__MODULE__{} = plan, nil), do: plan

  def attach_operation(%__MODULE__{} = plan, operation_id) when is_binary(operation_id),
    do: %{plan | operation_id: operation_id}

  @spec automated(t(), boolean()) :: t()
  def automated(%__MODULE__{} = plan, automated?) when is_boolean(automated?),
    do: %{plan | automated?: automated?}

  @spec submission(t()) :: submission()
  def submission(%__MODULE__{details: []}), do: :empty

  def submission(%__MODULE__{} = plan) do
    details = Enum.map(plan.details, &maybe_mark_automated(&1, plan.automated?))

    cond do
      plan.packaged? ->
        {:one, package(plan, details)}

      is_binary(plan.operation_id) and length(details) > 1 ->
        {:one, operation_package(plan, details)}

      is_binary(plan.operation_id) ->
        {:one, details |> List.first() |> rekey_detail(plan.operation_id)}

      length(details) == 1 ->
        {:one, List.first(details)}

      plan.automated? ->
        {:individual, details}

      true ->
        {:batch, details}
    end
  end

  defp package(plan, details) do
    package = Jobs.Package.new(plan.package_name, details, plan.package_log_on_start)
    %{package | id: plan.operation_id || plan.package_id}
  end

  defp operation_package(plan, details) do
    name = details |> List.first() |> Map.fetch!(:name)
    %{Jobs.Package.new(name, details, nil) | id: plan.operation_id}
  end

  defp maybe_mark_automated(detail, true), do: Jobs.Detail.set_automated(detail)
  defp maybe_mark_automated(detail, false), do: detail

  defp rekey_detail(%Jobs.Detail{id: previous_id, spec_list: specs} = detail, operation_id) do
    specs =
      Enum.map(specs, fn {spec, spec_id} ->
        {spec, String.replace_prefix(spec_id, previous_id, operation_id)}
      end)

    %{detail | id: operation_id, spec_list: specs}
  end
end
