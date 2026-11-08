defmodule Exdock.Server.Logging.Status.Dashboard do
  @moduledoc """
  Pure projection logic for job dashboard rows.

  Job lifecycle data remains canonical in `Status.jobs`; this module derives and
  updates the operator-facing rows using each registered job's presentation
  callbacks.
  """

  alias Exdock.Server.Logging.Status.{JobAdapter, JobRegistry, Lifecycle}
  alias Exdock.Status.Dashboard, as: DashboardContract
  alias Exdock.Status.Dashboard.Row

  @type entries :: DashboardContract.entries()
  @type t :: DashboardContract.t()

  @spec new() :: t()
  def new, do: JobRegistry.initial_dash()

  @spec add(t(), Lifecycle.t(), term(), term()) :: t()
  def add(
        dash,
        %Lifecycle{
          phase: :started,
          job_name: job_name,
          job_id: job_id,
          locations: locations
        },
        state,
        data
      ) do
    value = row_value(job_name, state, data)

    rows =
      Enum.reduce(locations, entries(dash, job_name), fn location, rows ->
        Map.put(rows, row_key(job_name, job_id, location, data), value)
      end)

    put_entries(dash, job_name, rows)
  end

  @spec refresh(t(), Lifecycle.t(), term()) :: t()
  def refresh(
        dash,
        %Lifecycle{
          phase: :updated,
          job_name: job_name,
          job_id: job_id,
          node: node,
          data: incoming_data
        },
        stored_data
      ) do
    before_key = row_key(job_name, job_id, node, incoming_data)
    after_key = row_key(job_name, job_id, node, stored_data)

    rows =
      case Map.get(entries(dash, job_name), before_key) do
        nil ->
          entries(dash, job_name)

        existing_row ->
          entries(dash, job_name)
          |> Map.delete(before_key)
          |> Map.put(after_key, Row.put_data(existing_row, row_data(job_name, stored_data)))
      end

    put_entries(dash, job_name, rows)
  end

  @spec finalize(t(), Lifecycle.t(), term()) :: t()
  def finalize(
        dash,
        %Lifecycle{
          phase: :finished,
          job_name: :container_recreate,
          job_id: job_id,
          node: node,
          data: %{"container" => container, "warning" => warning},
          error: nil
        },
        data
      )
      when is_binary(container) and is_binary(warning) do
    update_entries(dash, :container_recreate, fn rows ->
      Map.put(
        rows,
        row_key(:container_recreate, job_id, node, data),
        Row.new({:warning, warning}, row_data(:container_recreate, data)) |> Row.put_message({:string, warning})
      )
    end)
  end

  def finalize(
        dash,
        %Lifecycle{
          phase: :finished,
          job_name: job_name,
          job_id: job_id,
          node: node,
          error: nil
        },
        data
      ) do
    update_entries(dash, job_name, &Map.delete(&1, row_key(job_name, job_id, node, data)))
  end

  def finalize(
        dash,
        %Lifecycle{
          phase: :finished,
          job_name: job_name,
          job_id: job_id,
          node: node,
          error: error
        },
        data
      ) do
    update_entries(dash, job_name, fn rows ->
      Map.put(
        rows,
        row_key(job_name, job_id, node, data),
        row_value(job_name, {:error, error}, data)
      )
    end)
  end

  @spec put_message(t(), atom(), String.t(), term(), term(), term()) :: t()
  def put_message(dash, _job_name, _job_id, nil, _data, _message), do: dash
  def put_message(dash, _job_name, _job_id, _node, _data, nil), do: dash
  def put_message(dash, _job_name, _job_id, _node, nil, _message), do: dash

  def put_message(dash, job_name, job_id, node, data, message) do
    if JobRegistry.mirror_message?(job_name) do
      key = row_key(job_name, job_id, node, data)
      rows = entries(dash, job_name)

      case Map.fetch(rows, key) do
        :error -> dash
        {:ok, row} -> put_entries(dash, job_name, Map.put(rows, key, Row.put_message(row, message)))
      end
    else
      dash
    end
  end

  @spec errors?(t()) :: boolean()
  def errors?(dash) do
    Enum.any?(dash, fn {_job_name, rows} ->
      Enum.any?(rows, fn {_key, entry} -> error_entry?(entry) end)
    end)
  end

  @spec clear_errors(t()) :: t()
  def clear_errors(dash) do
    Map.new(dash, fn {job_name, rows} ->
      {job_name, Map.reject(rows, fn {_key, entry} -> error_entry?(entry) end)}
    end)
  end

  defp update_entries(dash, job_name, update) do
    put_entries(dash, job_name, update.(entries(dash, job_name)))
  end

  defp entries(dash, job_name), do: Map.get(dash, job_name, %{})
  defp put_entries(dash, job_name, rows), do: Map.put(dash, job_name, rows)

  defp row_key(job_name, job_id, location, data) do
    job_name
    |> JobRegistry.fetch!()
    |> JobAdapter.dash_key(job_id, location, data)
  end

  defp row_value(job_name, state, data), do: Row.new(state, row_data(job_name, data))

  defp row_data(job_name, data) do
    job_name
    |> JobRegistry.fetch!()
    |> JobAdapter.dash_data(data)
  end

  defp error_entry?(%Row{} = row), do: Row.attention?(row)
end
