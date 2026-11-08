defmodule Exdock.TestSupport.DockerEngineFake do
  @behaviour Exdock.Docker.Engine

  alias Exdock.Docker.Error

  @owner_key {__MODULE__, :owner}
  @results_key {__MODULE__, :results}

  def register_owner(owner) when is_pid(owner), do: Process.put(@owner_key, owner)

  def put_result(operation, result) when is_atom(operation) do
    Process.put(@results_key, Map.put(Process.get(@results_key, %{}), operation, result))
  end

  @impl true
  def connect do
    notify(:connect)
    :fake_connection
  end

  @impl true
  def list_containers(:fake_connection, retrieve_resources, opts) do
    notify({:list_containers, retrieve_resources, opts})
    result(:list_containers, {:ok, %{ok: [], errored: []}})
  end

  @impl true
  def list_images(:fake_connection) do
    notify(:list_images)
    result(:list_images, {:ok, %{ok: [], errored: []}})
  end

  @impl true
  def start_container(:fake_connection, id) do
    notify({:start_container, id})
    result(:start_container, {:ok, :started})
  end

  @impl true
  def container_image_info(:fake_connection, id) do
    notify({:container_image_info, id})
    result(:container_image_info, {:error, "not implemented"})
  end

  @impl true
  def recreate_container(:fake_connection, id, job_name, job_id) do
    notify({:recreate_container, id, job_name, job_id})
    result(:recreate_container, {:error, "not implemented"})
  end

  @impl true
  def stop_container(:fake_connection, id) do
    notify({:stop_container, id})
    result(:stop_container, {:error, "not implemented"})
  end

  @impl true
  def restart_container(:fake_connection, id) do
    notify({:restart_container, id})
    result(:restart_container, {:ok, :restarted})
  end

  @impl true
  def container_logs(:fake_connection, id, opts) do
    notify({:container_logs, id, opts})
    result(:container_logs, {:error, "not implemented"})
  end

  @impl true
  def container_resources(:fake_connection, id) do
    notify({:container_resources, id})
    result(:container_resources, {:error, "not implemented"})
  end

  @impl true
  def pull_image(:fake_connection, tag, stream_response, job_name, job_id) do
    notify({:pull_image, tag, stream_response, job_name, job_id})
    result(:pull_image, {:error, "not implemented"})
  end

  @impl true
  def delete_image(:fake_connection, id) do
    notify({:delete_image, id})
    result(:delete_image, {:error, "not implemented"})
  end

  defp notify(message) do
    if owner = Process.get(@owner_key), do: send(owner, {:docker_engine, message})
    :ok
  end

  defp result(operation, default) do
    @results_key
    |> Process.get(%{})
    |> Map.get(operation, default)
    |> normalize_error(operation)
  end

  defp normalize_error({:error, %Error{} = error}, _operation), do: {:error, error}

  defp normalize_error({:error, cause}, operation),
    do: {:error, Error.new(error_operation(operation), cause)}

  defp normalize_error(result, _operation), do: result

  defp error_operation(:list_containers), do: :container_list
  defp error_operation(:container_image_info), do: :container_inspect
  defp error_operation(:recreate_container), do: :container_recreate
  defp error_operation(:start_container), do: :container_start
  defp error_operation(:stop_container), do: :container_stop
  defp error_operation(:restart_container), do: :container_restart
  defp error_operation(:list_images), do: :image_list
  defp error_operation(:pull_image), do: :image_pull
  defp error_operation(:delete_image), do: :image_delete
  defp error_operation(operation), do: operation
end
