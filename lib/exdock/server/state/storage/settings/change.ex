defmodule Exdock.Server.State.Storage.Settings.Change do
  @moduledoc """
  Constructors for settings change payloads.
  """

  alias Exdock.Runtime.Mutation

  @doc """
  Set the default user's automation cron expression.
  """
  @spec cron(String.t()) :: Mutation.t()
  def cron(value) when is_binary(value) do
    Mutation.user_setting!(:cron_string, value)
  end
end
