defmodule Exdock.Domain.Container.Extended do
  alias Exdock.Domain.Container.Resources

  @derive Jason.Encoder
  defstruct logs: nil, resources: %Resources{}

  @type t :: %__MODULE__{
          logs: %{lines: [String.t()], time: DateTime.t()} | nil,
          resources: Resources.t()
        }

  @spec new() :: t()
  def new(), do: %__MODULE__{}

  @doc """
  Add a resources record.
  """
  @spec add_record(t(), Resources.Record.t() | nil, DateTime.t()) :: t()
  def add_record(%__MODULE__{resources: resources} = extended, record, %DateTime{} = now)
      when is_struct(record, Resources.Record) or is_nil(record) do
    %{extended | resources: Resources.add_record(resources || Resources.new(), record, now)}
  end

  @spec set_logs(t(), [String.t()], DateTime.t()) :: t()
  def set_logs(%__MODULE__{} = extended, lines, %DateTime{} = occurred_at) when is_list(lines) do
    %{extended | logs: %{lines: lines, time: occurred_at}}
  end
end
