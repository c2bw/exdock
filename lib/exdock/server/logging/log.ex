defmodule Exdock.Server.Logging.Log do
  @moduledoc """
  Log history entry and helpers.

  Logs are capped in memory and can represent either plain events or job-linked
  entries. Job-linked entries are later updated by job id as the operation
  finishes or fails.
  """

  defstruct id: nil,
            message_id: nil,
            message_data: nil,
            start_time: nil,
            end_time: nil,
            entry_data: nil,
            is_automated: false,
            hidden: false

  @max_entries 300

  @type job_status :: :started | :finished | :errored

  @type job_entry :: %{
          job_id: String.t(),
          status: job_status()
        }

  @type t :: %__MODULE__{
          id: String.t() | nil,
          message_id: atom(),
          message_data: any(),
          start_time: DateTime.t() | nil,
          end_time: DateTime.t() | nil,
          entry_data: job_entry() | nil,
          is_automated: boolean(),
          hidden: boolean()
        }
  @spec current_log(Exdock.Server.Logging.State.t()) :: [t()]
  def current_log(state), do: state.logs

  @doc """
    Adds a new log entry to the log history.

    Entries can be simple messages or job logs. Only the latest 300 entries are
    retained to keep the LiveView payload bounded.
  """
  @spec add_entry([t()], Exdock.Server.Logging.AppendEntry.t(), String.t(), DateTime.t()) :: [t()]
  def add_entry(log_history, %Exdock.Server.Logging.AppendEntry{} = input, id, %DateTime{} = started_at)
      when is_binary(id) do
    entry = %__MODULE__{
      id: id,
      message_id: input.message_name,
      message_data: input.message_data,
      start_time: started_at,
      end_time: nil,
      entry_data: new_job_entry(input.job_id),
      is_automated: input.automated?,
      hidden: input.hidden?
    }

    [entry | log_history] |> Enum.take(@max_entries)
  end

  defp new_job_entry(nil), do: nil
  defp new_job_entry(job_id) when is_binary(job_id), do: %{job_id: job_id, status: :started}

  @doc """
      Updates the status of a job in the log history.

      The job_id must be provided to update the log entry. If the job_id is not
      found in the log history, the log is unchanged.

  Options:
  - `:lazy` - If `true`, the status will only be updated if the status for this entry has not yet been updated.
  - `:unhide` - If `true`, the log entry will be marked as not-hidden.
  - `:change_message_data` - If provided, the message_data of the log entry will be updated with the provided key-value pair.
  """
  @spec update_entry([t()], String.t(), job_status(), DateTime.t(), Keyword.t()) :: [t()]
  def update_entry(log_history, job_id, status, %DateTime{} = completed_at, opts \\ []) do
    if is_nil(job_id), do: raise(ArgumentError, "job_id must be provided to update log entry")

    unhide_entry? = Keyword.get(opts, :unhide, false)

    Enum.map(log_history, fn entry ->
      if matching_job_entry?(entry, job_id) do
        entry
        |> maybe_unhide(unhide_entry?)
        |> update_entry_status(status, completed_at, opts)
      else
        entry
      end
    end)
  end

  @spec update_entry_status(t(), job_status(), DateTime.t(), Keyword.t()) :: t()
  defp update_entry_status(entry, status, completed_at, opts) do
    # Lazy updates preserve a final status when a later completion arrived first.
    status = effective_status(entry, status, Keyword.get(opts, :lazy, false))

    entry
    |> put_job_status(status, completed_at)
    |> maybe_change_message_data(Keyword.get(opts, :change_message_data))
  end

  defp effective_status(%__MODULE__{entry_data: %{status: current_status}}, _requested_status, true = _lazy?)
       when current_status != :started,
       do: current_status

  defp effective_status(%__MODULE__{}, requested_status, _lazy?), do: requested_status

  defp put_job_status(%__MODULE__{entry_data: entry_data} = entry, status, completed_at) do
    %{entry | end_time: completed_at, entry_data: %{entry_data | status: status}}
  end

  defp maybe_change_message_data(%__MODULE__{} = entry, nil), do: entry

  defp maybe_change_message_data(%__MODULE__{message_data: message_data} = entry, {key, value}) do
    %{entry | message_data: Map.put(message_data, key, value)}
  end

  @spec matching_job_entry?(t(), String.t()) :: boolean()
  defp matching_job_entry?(%__MODULE__{entry_data: nil}, _job_id), do: false
  defp matching_job_entry?(%__MODULE__{entry_data: %{job_id: entry_job_id}}, job_id), do: String.equivalent?(entry_job_id, job_id)

  @spec maybe_unhide(t(), boolean()) :: t()
  defp maybe_unhide(entry, true), do: %{entry | hidden: false}
  defp maybe_unhide(entry, false), do: entry
end
