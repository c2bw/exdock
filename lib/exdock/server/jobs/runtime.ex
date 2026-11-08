defmodule Exdock.Server.Jobs.Runtime do
  @moduledoc "Runtime process and publication targets used by the job dispatcher."

  alias Exdock.Events
  alias Exdock.Runtime.Port
  alias Exdock.Runtime.Coordinator
  alias Exdock.Server.Connection.TCPServer
  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.{Publisher, PublisherBehaviour}

  @enforce_keys [:jobs, :task_supervisor, :coordinator, :connection, :publisher, :pubsub, :events]
  defstruct [:jobs, :task_supervisor, :coordinator, :connection, :publisher, :pubsub, :events]

  @type t :: %__MODULE__{
          jobs: GenServer.server(),
          task_supervisor: GenServer.server(),
          coordinator: GenServer.server(),
          connection: GenServer.server(),
          publisher: module(),
          pubsub: atom(),
          events: module()
        }

  @spec new(keyword()) :: t()
  def new(opts \\ []) when is_list(opts) do
    publisher = Keyword.get(opts, :publisher, Publisher)
    events = Keyword.get(opts, :events, Events)

    %__MODULE__{
      jobs: Keyword.get(opts, :jobs, self()),
      task_supervisor: Keyword.get(opts, :task_supervisor, Jobs.TaskSupervisor),
      coordinator: Keyword.get(opts, :coordinator, Coordinator),
      connection: Keyword.get(opts, :connection, TCPServer),
      publisher: Port.validate_behaviour!(publisher, PublisherBehaviour, :jobs_publisher),
      pubsub: Keyword.get(opts, :pubsub, Exdock.PubSub),
      events: Port.validate_behaviour!(events, Exdock.Runtime.EventSink, :event_sink)
    }
  end

  @spec publisher_opts(t()) :: keyword()
  def publisher_opts(%__MODULE__{} = runtime),
    do: [pubsub: runtime.pubsub, events: runtime.events]
end
