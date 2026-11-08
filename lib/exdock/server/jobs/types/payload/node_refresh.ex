defmodule Exdock.Server.Jobs.Payload.NodeRefresh do
  @moduledoc "Metadata used to compare state before and after a node refresh."

  @enforce_keys [:init_containers, :log, :log_opts]
  defstruct [:init_containers, :log, :log_opts]

  @type t :: %__MODULE__{
          init_containers: %{String.t() => list()},
          log: map() | nil,
          log_opts: keyword()
        }

  @spec new(%{String.t() => list()}, map() | nil, keyword()) :: t()
  def new(init_containers, log, log_opts)
      when is_map(init_containers) and (is_map(log) or is_nil(log)) and is_list(log_opts),
      do: %__MODULE__{init_containers: init_containers, log: log, log_opts: log_opts}
end
