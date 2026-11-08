defmodule Exdock.Server.Jobs.Local.Releases.Context do
  @moduledoc """
  Runtime collaborators used while fetching repository releases.

  The default context connects release jobs to the provider HTTP adapter and
  job progress delivery. Tests can replace those boundaries while exercising
  the same concurrent fetcher used in production.
  """

  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.Local.Releases.HTTPRequest

  @release_fetch_concurrency 5
  @release_fetch_timeout_ms 120_000

  @type request_executor :: (HTTPRequest.t() -> HTTPRequest.result())
  @type update_publisher :: (Jobs.Update.t() -> term())

  @enforce_keys [:request_executor, :update_publisher, :max_concurrency, :timeout]
  defstruct [:request_executor, :update_publisher, :max_concurrency, :timeout]

  @type t :: %__MODULE__{
          request_executor: request_executor(),
          update_publisher: update_publisher(),
          max_concurrency: pos_integer(),
          timeout: timeout()
        }

  @doc """
  Returns the production release-fetch context.
  """
  @spec default() :: t()
  def default do
    %__MODULE__{
      request_executor: &HTTPRequest.request/1,
      update_publisher: &Jobs.job_update/1,
      max_concurrency: @release_fetch_concurrency,
      timeout: @release_fetch_timeout_ms
    }
  end

  @doc """
  Builds a context by replacing selected production collaborators.
  """
  @spec new(keyword()) :: t()
  def new(overrides \\ []) when is_list(overrides) do
    default()
    |> struct!(overrides)
    |> validate!()
  end

  @spec execute_request(t(), HTTPRequest.t()) :: HTTPRequest.result()
  def execute_request(%__MODULE__{request_executor: executor}, %HTTPRequest{} = request),
    do: executor.(request)

  @spec publish_update(t(), Jobs.Update.t()) :: term()
  def publish_update(%__MODULE__{update_publisher: publisher}, %Jobs.Update{} = update),
    do: publisher.(update)

  defp validate!(
         %__MODULE__{
           request_executor: request_executor,
           update_publisher: update_publisher,
           max_concurrency: max_concurrency,
           timeout: timeout
         } = context
       )
       when is_function(request_executor, 1) and is_function(update_publisher, 1) and
              is_integer(max_concurrency) and max_concurrency > 0 and
              (timeout == :infinity or (is_integer(timeout) and timeout > 0)),
       do: context

  defp validate!(_context), do: raise(ArgumentError, "invalid release fetch context")
end
