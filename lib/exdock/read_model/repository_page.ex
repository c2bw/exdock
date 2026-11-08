defmodule Exdock.ReadModel.RepositoryPage do
  @moduledoc """
  Public repository-fetch status exposed to delivery layers.
  """

  defstruct state: :unknown, last_check: nil

  @type state :: :unknown | :ok | :not_found | :rate_limit | :unsupported | :error
  @type t :: %__MODULE__{state: state(), last_check: DateTime.t() | nil}

  @spec from_domain(map() | nil) :: t()
  def from_domain(nil), do: %__MODULE__{}

  def from_domain(%{state: state, last_check: last_check}) do
    %__MODULE__{state: state, last_check: last_check}
  end
end
