defmodule Exdock.ClientLib.Container.Recreator.Failure do
  @moduledoc """
  Builds structured recreation errors with an operator-facing message.
  """

  alias Exdock.ClientLib.Utils
  alias Exdock.Docker.Error

  @type rollback_error :: {term(), term()}

  @spec build(Error.operation(), term(), [rollback_error()]) :: Error.t()
  def build(:image_unavailable = operation, image_tag, rollback_errors) do
    message =
      format_message(
        "No such image [#{image_tag}], aborting RECREATE operation. Please pull the image first.",
        rollback_errors
      )

    Error.new(operation, image_tag, message: message)
  end

  def build(operation, reason, rollback_errors) do
    message =
      format_message(
        "#{operation_label(operation)}: #{Utils.error_message(reason)}",
        rollback_errors
      )

    Error.new(operation, reason, message: message)
  end

  defp format_message(message, []), do: message

  defp format_message(message, rollback_errors) do
    rollback =
      Enum.map_join(rollback_errors, ", ", fn {operation, reason} ->
        "#{operation_label(operation)}: #{Utils.error_message(reason)}"
      end)

    "#{message}; rollback errors: #{rollback}"
  end

  defp operation_label({operation, network}), do: "#{operation} [#{network}]"
  defp operation_label(operation), do: to_string(operation)
end
