defmodule Exdock.Domain.Repository.Metadata do
  defstruct [
    :state,
    :last_check
  ]

  @default_page_state :ok
  @default_last_check nil
  @page_states [:ok, :not_found, :rate_limit, :unsupported, :error]

  @type page_state :: :ok | :not_found | :rate_limit | :unsupported | :error
  @type t :: %__MODULE__{
          state: page_state(),
          last_check: DateTime.t() | nil
        }

  @doc false
  @spec from_persisted(map()) :: t()
  def from_persisted(%{releases_page: state, last_check: last_check}) do
    %__MODULE__{state: state, last_check: last_check}
  end

  @spec set_last_check(t(), DateTime.t()) :: t()
  def set_last_check(%__MODULE__{} = m, %DateTime{} = t \\ DateTime.utc_now()) do
    # Repository metadata is stored in a `:utc_datetime` field, which rejects
    # microseconds. Truncate at the structure boundary so every caller persists
    # a database-compatible timestamp.
    %{m | last_check: DateTime.truncate(t, :second)}
  end

  @spec set_state(t(), page_state()) :: t()
  def set_state(%__MODULE__{} = m, state) when state in @page_states, do: %{m | state: state}

  @spec default() :: t()
  def default() do
    %__MODULE__{
      state: @default_page_state,
      last_check: @default_last_check
    }
  end
end
