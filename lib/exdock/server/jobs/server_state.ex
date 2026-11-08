defmodule Exdock.Server.Jobs.ServerState do
  @moduledoc false

  alias Exdock.Server.Jobs.{Runtime, State}

  @enforce_keys [:domain, :runtime]
  defstruct [:domain, :runtime]

  @type t :: %__MODULE__{domain: State.t(), runtime: Runtime.t()}

  @spec new(Runtime.t()) :: t()
  def new(%Runtime{} = runtime), do: %__MODULE__{domain: State.new(), runtime: runtime}

  @spec put_domain(t(), State.t()) :: t()
  def put_domain(%__MODULE__{} = state, %State{} = domain), do: %{state | domain: domain}
end
