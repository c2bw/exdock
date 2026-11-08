defmodule Exdock.ClientLib.Jobs.Context do
  @moduledoc false

  alias Exdock.Docker.Engine

  @enforce_keys [:engine]
  defstruct [:engine]

  @type t :: %__MODULE__{engine: module()}

  @spec new(module()) :: t()
  def new(engine) when is_atom(engine), do: %__MODULE__{engine: engine}

  @spec runtime() :: t()
  def runtime, do: new(Engine.adapter())

  @spec connect(t()) :: {module(), term()}
  def connect(%__MODULE__{engine: engine}) do
    {engine, engine.connect()}
  end
end
