defmodule Exdock.Runtime.Mutation.Payload.UserSetting do
  @moduledoc "Typed user-setting mutation payload."

  @enforce_keys [:key, :value]
  defstruct [:key, :value]

  @type t :: %__MODULE__{key: atom(), value: term()}
end
