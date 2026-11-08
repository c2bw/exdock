defmodule Exdock.Docker.Local.Image.PullTransport do
  @moduledoc """
  Transport contract for Docker image-pull response streams.
  """

  @callback stream(term(), String.t(), pid()) :: {:ok, term()} | {:error, term()}
end
