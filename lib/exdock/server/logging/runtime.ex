defmodule Exdock.Server.Logging.Runtime do
  @moduledoc "Runtime process and effect targets used by the logging server."

  alias Exdock.Events
  alias Exdock.Runtime.Port
  alias Exdock.Server.{Broadcast, Jobs, Notifier}
  alias Exdock.Server.Logging.Context

  @enforce_keys [:broadcast, :jobs, :notifier, :pubsub, :events, :context_provider]
  defstruct [:broadcast, :jobs, :notifier, :pubsub, :events, :context_provider]

  @type t :: %__MODULE__{
          broadcast: GenServer.server(),
          jobs: GenServer.server(),
          notifier: GenServer.server(),
          pubsub: atom(),
          events: module(),
          context_provider: (-> Context.t())
        }

  @spec new(keyword()) :: t()
  def new(opts \\ []) when is_list(opts) do
    events = Keyword.get(opts, :events, Events)
    context_provider = Keyword.get(opts, :context_provider, &Context.runtime/0)

    unless is_function(context_provider, 0) do
      raise ArgumentError, "invalid logging context provider; expected a zero-arity function"
    end

    %__MODULE__{
      broadcast: Keyword.get(opts, :broadcast, Broadcast),
      jobs: Keyword.get(opts, :jobs, Jobs),
      notifier: Keyword.get(opts, :notifier, Notifier),
      pubsub: Keyword.get(opts, :pubsub, Exdock.PubSub),
      events: Port.validate_behaviour!(events, Exdock.Runtime.EventSink, :event_sink),
      context_provider: context_provider
    }
  end
end
