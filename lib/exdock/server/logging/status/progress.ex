defmodule Exdock.Server.Logging.Status.Progress do
  @moduledoc """
  Shared progress updates for async status jobs.

  Registry and release fetches both receive one update per async request. The
  update must first persist the aggregate counter and headline message, then log
  any per-item error without losing that progress. Keeping that ordering here
  avoids each status module reimplementing the same nested-map mutation.
  """

  alias Exdock.Server.Logging.Status.Utils

  @spec bump(map(), atom(), String.t(), atom(), String.t(), (map() -> String.t())) :: map()
  def bump(%{jobs: jobs} = status, job_name, job_id, counter_key, job_label, message_fun)
      when is_map(jobs) and
             is_atom(job_name) and is_binary(job_id) and is_atom(counter_key) and
             is_function(message_fun, 1) do
    job_data =
      status
      |> Utils.get_job_data(job_name, job_id)
      |> increment_counter(counter_key)

    status
    |> Utils.set_job_data(job_name, job_id, job_data)
    |> Utils.set_job_message(job_label, message_fun.(job_data.data))
  end

  @spec maybe_log_error(map(), term(), term(), DateTime.t(), (term(), term() -> String.t())) :: map()
  def maybe_log_error(%{errors: errors} = status, _data, nil, %DateTime{}, _message_fun)
      when is_list(errors),
      do: status

  def maybe_log_error(%{errors: errors} = status, data, error, %DateTime{} = occurred_at, message_fun)
      when is_list(errors) and is_function(message_fun, 2) do
    Utils.add_entry_to_errors_log(status, message_fun.(data, error), occurred_at)
  end

  defp increment_counter(%{data: data} = job_data, counter_key) when is_map(data) do
    %{job_data | data: Map.update!(data, counter_key, &(&1 + 1))}
  end
end
