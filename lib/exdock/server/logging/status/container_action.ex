defmodule Exdock.Server.Logging.Status.ContainerAction do
  @moduledoc false

  defmacro __using__(opts) do
    action_label = Keyword.fetch!(opts, :action_label)
    error_action = Keyword.fetch!(opts, :error_action)
    recreate? = Keyword.get(opts, :recreate, false)

    add_definition =
      if recreate? do
        quote do
          @impl true
          def add(status, %Lifecycle{
                locations: locations,
                data: %ContainerPayload{container: container}
              }) do
            ContainerAction.add_recreate(status, unquote(action_label), locations, container)
          end
        end
      else
        quote do
          @impl true
          def add(status, %Lifecycle{
                locations: locations,
                data: %ContainerPayload{container: container}
              }) do
            ContainerAction.add(status, unquote(action_label), locations, container)
          end
        end
      end

    quote do
      use Exdock.Server.Logging.Status.JobBehaviour

      alias Exdock.Server.Jobs.Payload.ContainerAction, as: ContainerPayload
      alias Exdock.Server.Logging.Status.ContainerAction
      alias Exdock.Server.Logging.Status.Lifecycle

      @impl true
      defdelegate data_init(data), to: ContainerAction

      @impl true
      defdelegate log(data), to: ContainerAction

      @impl true
      defdelegate dash_key(job_id, location, data), to: ContainerAction

      @impl true
      defdelegate dash_data(data), to: ContainerAction

      unquote(add_definition)

      @impl true
      def update(status, %Lifecycle{}), do: ContainerAction.update(status)

      @impl true
      def result(
            status,
            %Lifecycle{node: node, data: data, error: error, occurred_at: occurred_at}
          ) do
        ContainerAction.result(
          status,
          unquote(action_label),
          unquote(error_action),
          node,
          data,
          error,
          occurred_at
        )
      end

      defoverridable result: 2
    end
  end

  use Exdock.Server.Logging.Status.JobBehaviour

  alias Exdock.Server.Logging.Status.ImageAction
  alias Exdock.Server.Logging.Status.Lifecycle
  alias Exdock.Server.Jobs.Payload.ContainerAction

  @recreate_verb "recreating"
  @actions %{
    container_start: %{label: "Start Container", error_action: "start"},
    container_stop: %{label: "Stop Container", error_action: "stop"},
    container_restart: %{label: "Restart Container", error_action: "restart"}
  }

  @impl true
  def data_init(data), do: container_label(data)

  @impl true
  def log(%{node: node} = data), do: {{node, container_label(data)}, []}

  @impl true
  def add(
        status,
        %Lifecycle{
          job_name: job_name,
          locations: locations,
          data: %ContainerAction{container: container}
        }
      )
      when is_map_key(@actions, job_name) do
    %{label: label} = Map.fetch!(@actions, job_name)
    add(status, label, locations, container)
  end

  def add(status, action_label, locations, value) do
    ImageAction.add(status, action_label, locations, value, nil)
  end

  def add_recreate(status, action_label, locations, container) do
    ImageAction.add(status, action_label, locations, container, @recreate_verb)
  end

  def update(status), do: status

  @impl true
  def update(status, %Lifecycle{job_name: job_name})
      when is_map_key(@actions, job_name),
      do: update(status)

  @impl true
  def result(
        status,
        %Lifecycle{job_name: job_name, node: node, data: data, error: error, occurred_at: occurred_at}
      )
      when is_map_key(@actions, job_name) do
    %{label: label, error_action: error_action} = Map.fetch!(@actions, job_name)
    result(status, label, error_action, node, data, error, occurred_at)
  end

  # Container actions emit generic success messages; only errors carry a
  # dedicated label from the caller.
  def result(status, action_label, _error_label, node, data, nil, %DateTime{})
      when is_binary(action_label) do
    ImageAction.result_success(status, action_label, nil, data, node)
  end

  def result(status, action_label, error_label, node, data, error, %DateTime{} = occurred_at)
      when is_binary(action_label) do
    ImageAction.result_error(status, action_label, error_label, node, data, error, occurred_at)
  end

  @impl true
  defdelegate dash_key(job_id, location, data), to: ImageAction

  @impl true
  defdelegate dash_data(data), to: ImageAction

  defp container_label(%ContainerAction{container: container}), do: container
  defp container_label(%{name: name}), do: name
  defp container_label(%{container: container}), do: container
end
