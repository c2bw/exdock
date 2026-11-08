defmodule Exdock.Server.Logging.Status.JobAdapter do
  @moduledoc false

  alias Exdock.Server.Logging.Status.Lifecycle

  defstruct [:module, completion_log?: false, mirror_message?: false]

  @type t :: %__MODULE__{
          module: module(),
          completion_log?: boolean(),
          mirror_message?: boolean()
        }

  def data_init(%__MODULE__{module: module}, data), do: module.data_init(data)
  def log(%__MODULE__{module: module}, data), do: module.log(data)
  def add(status, %__MODULE__{module: module}, lifecycle), do: module.add(status, lifecycle)
  def update(status, %__MODULE__{module: module}, lifecycle), do: module.update(status, lifecycle)
  def result(status, %__MODULE__{module: module}, lifecycle), do: module.result(status, lifecycle)

  def update_effects(%__MODULE__{module: module}, status, lifecycle),
    do: module.update_effects(status, lifecycle)

  def result_effects(%__MODULE__{module: module}, status, lifecycle),
    do: module.result_effects(status, lifecycle)

  def completion_log_options(
        %__MODULE__{module: module, completion_log?: true},
        status,
        %Lifecycle{} = lifecycle
      ),
      do: module.completion_log_options(status, lifecycle)

  def completion_log_options(%__MODULE__{}, _status, %Lifecycle{}), do: [lazy: true]

  def dash_key(%__MODULE__{module: module}, job_id, location, data),
    do: module.dash_key(job_id, location, data)

  def dash_data(%__MODULE__{module: module}, data), do: module.dash_data(data)
end
