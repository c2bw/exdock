defmodule Exdock.Server.Logging.AppendEntry do
  @moduledoc """
  Named input for appending an entry to the user-visible log.

  The input travels across logging and state-effect boundaries so optional
  flags cannot be confused by their position in a tuple or argument list.
  """

  @enforce_keys [:message_name, :message_data]
  defstruct [:message_name, :message_data, :job_id, automated?: false, hidden?: false, broadcast?: true]

  @type t :: %__MODULE__{
          message_name: atom(),
          message_data: term(),
          job_id: String.t() | nil,
          automated?: boolean(),
          hidden?: boolean(),
          broadcast?: boolean()
        }

  @spec new(atom(), term()) :: t()
  def new(message_name, message_data), do: new(message_name, message_data, nil, [])

  @spec new(atom(), term(), String.t() | nil) :: t()
  def new(message_name, message_data, job_id) when is_binary(job_id) or is_nil(job_id),
    do: new(message_name, message_data, job_id, [])

  @spec new(atom(), term(), keyword()) :: t()
  def new(message_name, message_data, opts) when is_list(opts),
    do: new(message_name, message_data, nil, opts)

  @spec new(atom(), term(), String.t() | nil, keyword()) :: t()
  def new(message_name, message_data, job_id, opts)
      when is_atom(message_name) and (is_binary(job_id) or is_nil(job_id)) and is_list(opts) do
    %__MODULE__{
      message_name: message_name,
      message_data: message_data,
      job_id: job_id,
      automated?: Keyword.get(opts, :automated, false),
      hidden?: Keyword.get(opts, :hidden, false),
      broadcast?: Keyword.get(opts, :broadcast, true)
    }
  end
end
