defmodule Exdock.Server.ClientIngress do
  @moduledoc """
  Validates authenticated client-message identity before applying it to state.
  """

  alias Exdock.Protocol.Messages
  alias Exdock.Server.Jobs
  alias Exdock.Server.State
  alias Exdock.Server.Connection.TCPServer.ClientRegistry

  require Logger

  @spec accept(State.t(), String.t(), pid(), term(), GenServer.server()) :: State.t()
  def accept(%State{} = state, client_name, handler, message, registry \\ ClientRegistry) when is_binary(client_name) do
    with :ok <- validate_owner(client_name, handler, registry),
         {:ok, message} <- validate(message, client_name) do
      State.ClientMessages.commit(state, message)
    else
      {:error, reason} ->
        Logger.warning("Rejected authenticated client message: #{inspect(reason)}")
        state
    end
  end

  @spec validate_owner(String.t(), pid(), GenServer.server()) :: :ok | {:error, atom()}
  def validate_owner(client_name, handler, registry \\ ClientRegistry) do
    case ClientRegistry.fetch(client_name, registry) do
      {:ok, ^handler} -> :ok
      _missing_or_replaced -> {:error, :stale_connection}
    end
  catch
    :exit, _reason -> {:error, :connection_registry_unavailable}
  end

  @spec validate(term(), String.t()) :: {:ok, term()} | {:error, term()}
  def validate(message, client_name) when is_binary(client_name) do
    case message_node(message) do
      ^client_name -> {:ok, message}
      node when is_binary(node) -> {:error, {:node_mismatch, node, client_name}}
      _other -> {:error, :invalid_message_identity}
    end
  end

  defp message_node(%Messages.JobResult{result: %Jobs.Result{node: node}}), do: node
  defp message_node(%Messages.Update{node: node}), do: node
  defp message_node(%Messages.AsyncResult{node: node}), do: node
  defp message_node(_message), do: nil
end
