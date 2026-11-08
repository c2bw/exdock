defmodule Exdock.Server.Jobs.Helper do
  @doc """
  Generate a unique ID.
  """
  @spec generate_id() :: String.t()
  def generate_id(), do: Ecto.UUID.generate()

  @doc """
  Generate a unique ID for a sub-job based on the parent job ID.
  ## Format: `parent_id.sub_id`
  """
  @spec generate_sub_id(String.t()) :: String.t()
  def generate_sub_id(parent) when is_binary(parent), do: "#{parent}.#{generate_id()}"
end
