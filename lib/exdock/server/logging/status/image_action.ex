defmodule Exdock.Server.Logging.Status.ImageAction do
  @moduledoc false

  defmacro __using__(opts) do
    action_label = Keyword.fetch!(opts, :action_label)
    add_verb = Keyword.fetch!(opts, :add_verb)
    result_verb = Keyword.fetch!(opts, :result_verb)
    error_action = Keyword.fetch!(opts, :error_action)
    payload_field = Keyword.fetch!(opts, :payload_field)

    quote do
      use Exdock.Server.Logging.Status.JobBehaviour

      alias Exdock.Server.Jobs.Payload.ImageAction, as: ImagePayload
      alias Exdock.Server.Logging.Status.ImageAction
      alias Exdock.Server.Logging.Status.Lifecycle

      @impl true
      defdelegate data_init(data), to: ImageAction

      @impl true
      defdelegate log(data), to: ImageAction

      @impl true
      defdelegate dash_key(job_id, location, data), to: ImageAction

      @impl true
      defdelegate dash_data(data), to: ImageAction

      @impl true
      def add(status, %Lifecycle{locations: locations, data: %ImagePayload{} = payload}) do
        ImageAction.add(
          status,
          unquote(action_label),
          locations,
          Map.fetch!(payload, unquote(payload_field)),
          unquote(add_verb)
        )
      end

      @impl true
      def update(status, %Lifecycle{}), do: ImageAction.update(status)

      @impl true
      def result(status, %Lifecycle{node: node, data: data, error: nil}) do
        ImageAction.result_success(
          status,
          unquote(action_label),
          unquote(result_verb),
          data,
          node
        )
      end

      def result(
            status,
            %Lifecycle{node: node, data: data, error: error, occurred_at: occurred_at}
          ) do
        ImageAction.result_error(
          status,
          unquote(action_label),
          unquote(error_action),
          node,
          data,
          error,
          occurred_at,
          &format_error_data/1
        )
      end

      def format_error_data(data), do: data
      defoverridable format_error_data: 1
    end
  end

  alias Exdock.Server.Logging.Status.Utils
  alias Exdock.Server.Jobs.Payload.ImageAction

  def data_init(%ImageAction{image_tag: image_tag}) when is_binary(image_tag), do: image_tag
  def data_init(%ImageAction{image_id: image_id}) when is_binary(image_id), do: image_id

  def log(%ImageAction{node: node, image_tag: image_tag}) when is_binary(image_tag),
    do: {{node, image_tag}, []}

  def log(%ImageAction{node: node, image_tags: image_tags}), do: {{node, image_tags}, []}

  def add(status, label, locations, value, verb),
    do: Utils.set_job_message(status, label, action_message(value, locations, verb))

  def update(status), do: status

  def result_success(status, label, verb, data, node) do
    Utils.set_job_message(status, label, result_success_message(verb, data, node))
  end

  def result_error(status, label, error_label, node, data, error, occurred_at, format_data_for_log_fn \\ & &1) do
    error_result_messages(error_label, node, data, error, format_data_for_log_fn)
    |> apply_error_result(status, label, occurred_at)
  end

  def dash_key(_job_id, location, data), do: {location, data}
  def dash_data(_data), do: nil

  defp apply_error_result(%{headline: headline, log_entry: log_entry}, status, label, occurred_at) do
    status
    |> Utils.add_entry_to_errors_log(log_entry, occurred_at)
    |> Utils.set_job_message(label, headline, true)
  end

  defp action_message(value, locations, nil), do: "[#{value}] on #{inspect(locations)}"
  defp action_message(value, locations, verb), do: "#{verb} [#{value}] on #{inspect(locations)}"

  defp result_success_message(verb, data, node) when is_nil(verb) or verb == "",
    do: "OK: [#{data}] on [#{node}]"

  defp result_success_message(verb, data, node),
    do: "OK: #{verb} [#{data}] on [#{node}]"

  defp result_error_message(data, node, error), do: "[#{data}] on [#{node}]: #{inspect(error)}"

  defp result_error_entry_message(error_label, node, data, error, format_data_for_log_fn),
    do: "#{error_label} [#{node}, #{format_data_for_log_fn.(data)}]: #{inspect(error)}"

  defp error_result_messages(error_label, node, data, error, format_data_for_log_fn) do
    %{
      headline: result_error_message(data, node, error),
      log_entry: result_error_entry_message(error_label, node, data, error, format_data_for_log_fn)
    }
  end
end
