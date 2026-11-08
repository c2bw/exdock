defmodule Exdock.Server.Logging.Status.ImagePull do
  use Exdock.Server.Logging.Status.ImageAction,
    action_label: "Pull Image",
    add_verb: "pulling",
    result_verb: "pulled",
    error_action: "pull image",
    payload_field: :image_tag
end
