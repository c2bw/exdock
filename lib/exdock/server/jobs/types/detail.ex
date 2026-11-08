defmodule Exdock.Server.Jobs.Detail do
  @moduledoc """
  High-level job request queued by the server.

  A detail has one public lifecycle id and one or more executable specs. Specs
  allow a single logical job, such as a cluster refresh, to fan out into multiple
  local or remote executions while still reporting through the same detail id.
  """

  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.Payload
  alias Exdock.Runtime.Command.Workflow

  defstruct [
    :name,
    :id,
    :is_automated,
    :start,
    :start_requirements,
    :continuation,
    :spec_list
  ]

  @type start_requirements :: :none | :success
  @type start_trigger :: :instant | {:finish, String.t()}
  @type start_event :: :instant | {:finish, String.t(), Payload.error()}

  @type t :: %__MODULE__{
          name: atom(),
          id: String.t(),
          is_automated: boolean(),
          start: start_trigger(),
          start_requirements: start_requirements(),
          continuation: Workflow.t() | nil,
          spec_list: [{Jobs.Spec.t(), String.t()}]
        }

  @spec new(atom(), Jobs.Spec.t() | list(Jobs.Spec.t()), keyword()) :: t()
  def new(name, spec_or_specs, opts \\ [])
  def new(name, %Jobs.Spec{} = spec, opts), do: new(name, List.wrap(spec), opts)

  def new(name, [_ | _] = specs, opts) do
    validate_specs!(specs)

    options = detail_options(opts)
    detail_id = Jobs.Helper.generate_id()

    # Single-spec jobs reuse the detail id. Multi-spec jobs get sub-ids so
    # each executable unit can be tracked without losing the parent id.
    spec_list = build_spec_list(specs, detail_id)

    %__MODULE__{
      name: name,
      id: detail_id,
      is_automated: false,
      start: options.trigger,
      start_requirements: options.requirements,
      continuation: options.continuation,
      spec_list: spec_list
    }
  end

  @doc """
  Return true when this detail is chained to the given finished job id.
  """
  @spec finish_trigger?(t(), String.t()) :: boolean()
  def finish_trigger?(%__MODULE__{start: {:finish, id} = _trigger}, id) when is_binary(id), do: true
  def finish_trigger?(%__MODULE__{start: _trigger}, id) when is_binary(id), do: false

  @doc """
  Return true if the queue event satisfies this detail's trigger.

  `:success` requirements only allow the detail to run when the upstream finish
  event carries a nil error.
  """
  @spec runnable?(t(), start_event()) :: boolean()
  def runnable?(%__MODULE__{start: :instant}, :instant), do: true
  def runnable?(%__MODULE__{start: {:finish, id}, start_requirements: :none}, {:finish, id, _error}), do: true
  def runnable?(%__MODULE__{start: {:finish, id}, start_requirements: :success}, {:finish, id, nil}), do: true
  def runnable?(%__MODULE__{}, _), do: false

  @doc """
  Chain this detail to the result of another detail.

  This only rewrites the start trigger; the returned detail still has to be
  added to the job handler.
  """
  @spec chain_to(t(), t(), start_requirements()) :: t()
  def chain_to(%__MODULE__{} = detail, %__MODULE__{id: prev_id} = _p, requirements \\ :success) when is_atom(requirements) do
    trigger = {:finish, prev_id}
    %{detail | start: trigger, start_requirements: requirements}
  end

  defp validate_specs!(specs) do
    unless Enum.all?(specs, &match?(%Jobs.Spec{}, &1)) do
      raise ArgumentError, "specs must be a list of Jobs.Spec"
    end
  end

  defp detail_options(opts) do
    %{
      trigger: Keyword.get(opts, :trigger, :instant),
      requirements: Keyword.get(opts, :requirements, :none),
      continuation: Keyword.get(opts, :continuation, nil)
    }
  end

  defp build_spec_list([%Jobs.Spec{} = spec], detail_id), do: [{spec, detail_id}]
  defp build_spec_list(specs, detail_id), do: Enum.map(specs, &spec_with_generated_sub_id(&1, detail_id))

  defp spec_with_generated_sub_id(%Jobs.Spec{} = spec, detail_id), do: {spec, Jobs.Helper.generate_sub_id(detail_id)}

  @doc """
  Set the named workflow continuation to run after successful completion.
  """
  @spec set_continuation(t(), Workflow.t()) :: t()
  def set_continuation(%__MODULE__{} = detail, %Workflow{} = continuation),
    do: %{detail | continuation: continuation}

  @doc """
  Set the automated flag to true.
  """
  @spec set_automated(t()) :: t()
  def set_automated(%__MODULE__{} = detail), do: %{detail | is_automated: true}
end
