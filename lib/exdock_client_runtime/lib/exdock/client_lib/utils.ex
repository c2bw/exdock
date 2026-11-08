defmodule Exdock.ClientLib.Utils do
  alias Exdock.Docker.Error

  @async_stream_options [timeout: :infinity]

  @doc """
    Runs independent Docker lookups without Task's five-second default timeout.

    The Docker HTTP adapter owns the request timeout. Adding a shorter timeout
    here would turn a slow, valid Docker response into a crashed node refresh.
  """
  @spec async_stream(Enumerable.t(), (term() -> term())) :: Enumerable.t()
  def async_stream(enumerable, function) when is_function(function, 1) do
    Task.async_stream(enumerable, function, @async_stream_options)
  end

  @doc false
  @spec async_stream_options() :: keyword()
  def async_stream_options, do: @async_stream_options

  @doc "Wraps a raw Docker failure without discarding transport metadata."
  @spec docker_error(Error.operation(), term(), keyword()) :: Error.t()
  def docker_error(operation, cause, opts \\ [])

  def docker_error(_operation, %Error{} = error, _opts), do: error
  def docker_error(operation, cause, opts), do: Error.new(operation, cause, opts)

  @doc "Renders a Docker failure for a log or other human-facing boundary."
  @spec error_message(term()) :: String.t()
  def error_message(%Error{} = error), do: Error.message(error)
  def error_message(error), do: Error.new(:unknown, error) |> Error.message()
end
