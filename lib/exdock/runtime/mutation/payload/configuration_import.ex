defmodule Exdock.Runtime.Mutation.Payload.ConfigurationImport do
  @moduledoc "Typed server-configuration import mutation payload."

  alias Exdock.Configuration

  @enforce_keys [:configuration]
  defstruct [:configuration]

  @type t :: %__MODULE__{configuration: Configuration.t()}
end
