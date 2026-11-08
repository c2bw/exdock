defmodule Exdock.Server.State.Storage.Images.Info.Data do
  @moduledoc """
  Size and count summary for one filtered image collection.
  """

  alias Exdock.Server.State.Storage.Images.Info.Counters

  defstruct total_bytesize: 0,
            shared_bytesize: 0,
            images_count: 0,
            counters: %Counters{}

  @type t :: %__MODULE__{
          total_bytesize: integer(),
          shared_bytesize: integer(),
          images_count: integer(),
          counters: Counters.t()
        }
end
