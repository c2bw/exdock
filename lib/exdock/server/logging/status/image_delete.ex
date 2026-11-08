defmodule Exdock.Server.Logging.Status.ImageDelete do
  use Exdock.Server.Logging.Status.ImageAction,
    action_label: "Delete Image",
    add_verb: "deleting",
    result_verb: "deleted",
    error_action: "delete image",
    payload_field: :image_id

  def format_error_data(data), do: "#{String.slice(data, 7, 10)}.."
end
