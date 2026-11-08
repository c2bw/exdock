defmodule Exdock.Server.Jobs.Payload.RegistryFetch do
  @moduledoc "Registry metadata requests attached to a local fetch job."

  @enforce_keys [:image_requests]
  defstruct [:image_requests]

  @type request :: %{required(:tag) => String.t(), required(:platform) => String.t()}
  @type t :: %__MODULE__{image_requests: [request()]}

  @spec new([request()]) :: t()
  def new(image_requests) when is_list(image_requests),
    do: %__MODULE__{image_requests: image_requests}
end
