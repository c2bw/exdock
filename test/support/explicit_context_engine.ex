defmodule Exdock.TestSupport.ExplicitContextEngine do
  @moduledoc false

  def connect, do: :explicit_context_connection

  def start_container(:explicit_context_connection, _id), do: {:error, :explicit_context}
end
