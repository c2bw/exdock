defmodule Exdock.Runtime.Coordinator do
  @moduledoc """
  Message boundary for the process that owns authoritative runtime state.

  Callers depend on this API instead of the GenServer implementation module,
  keeping jobs, connections, effects, and read models independent from the
  coordinator callback implementation.
  """

  alias Exdock.Runtime.{Command, Mutation, Query}

  @server_name __MODULE__

  @type admission_result ::
          :ok
          | {:error, {:runtime_unavailable, :not_found | :timeout}}
          | {:error, {:runtime_failure, term()}}

  @spec submit(Ecto.UUID.t(), Command.internal_t(), keyword()) :: admission_result()
  def submit(operation_id, command, opts \\ [])
      when is_binary(operation_id) and is_list(opts) do
    {server, command_opts} = Keyword.pop(opts, :server, @server_name)
    {admission_timeout, command_opts} = Keyword.pop(command_opts, :admission_timeout, 5_000)
    safe_call(server, {:submit_command, operation_id, command, command_opts}, admission_timeout)
  end

  @spec submit_periodic_job(Ecto.UUID.t(), GenServer.server()) :: admission_result()
  def submit_periodic_job(operation_id, server \\ @server_name) when is_binary(operation_id),
    do: safe_call(server, {:submit_periodic_job, operation_id}, 5_000)

  @spec command(Ecto.UUID.t() | nil, Command.internal_t(), keyword()) :: :ok
  def command(operation_id, command, opts \\ [])
      when (is_binary(operation_id) or is_nil(operation_id)) and is_list(opts) do
    {server, command_opts} = Keyword.pop(opts, :server, @server_name)
    message = {:command, operation_id, command, command_opts}

    case Keyword.get(command_opts, :delay, 0) do
      delay when is_integer(delay) and delay > 0 ->
        Process.send_after(server, delayed_command(message), delay)

      _delay ->
        GenServer.cast(server, message)
    end

    :ok
  end

  @spec client_message(String.t(), term(), GenServer.server()) :: :ok
  def client_message(client_name, message, server \\ @server_name) when is_binary(client_name),
    do: cast(server, {:client_message, self(), client_name, message})

  @spec run_periodic_job() :: :ok
  def run_periodic_job, do: cast(@server_name, {:run_periodic_job})

  @spec run_periodic_job(Ecto.UUID.t()) :: :ok
  def run_periodic_job(operation_id) when is_binary(operation_id),
    do: run_periodic_job(operation_id, @server_name)

  @spec run_periodic_job(Ecto.UUID.t(), GenServer.server()) :: :ok
  def run_periodic_job(operation_id, server) when is_binary(operation_id),
    do: cast(server, {:run_periodic_job, operation_id})

  @spec change_periodic_job(String.t(), GenServer.server()) :: :ok
  def change_periodic_job(cron, server \\ @server_name) when is_binary(cron),
    do: cast(server, {:change_periodic_job, cron})

  @spec state_change(Mutation.t(), GenServer.server()) :: :ok
  def state_change(%Mutation{} = change, server \\ @server_name),
    do: cast(server, {:state_change, change})

  @spec commit_state_change(Mutation.t(), GenServer.server()) :: :ok | {:error, term()}
  def commit_state_change(%Mutation{} = change, server \\ @server_name),
    do: GenServer.call(server, {:commit_state_change, change}, :infinity)

  @spec query(Query.t(), GenServer.server()) :: Query.result()
  def query(query, server \\ @server_name), do: GenServer.call(server, {:query, query})

  @spec node_is_up(String.t(), map(), GenServer.server()) :: :ok
  def node_is_up(node, metadata, server \\ @server_name)
      when is_binary(node) and is_map(metadata),
      do: cast(server, {:node_is_up, node, metadata})

  @spec node_is_down(String.t(), GenServer.server()) :: :ok
  def node_is_down(node, server \\ @server_name) when is_binary(node),
    do: cast(server, {:node_is_down, node})

  @spec connections_reset(GenServer.server()) :: :ok
  def connections_reset(server \\ @server_name), do: cast(server, :connections_reset)

  @spec delayed_command(tuple()) :: tuple()
  defp delayed_command({:command, operation_id, command, opts}),
    do: {:delayed_command, operation_id, command, opts}

  @spec cast(GenServer.server(), term()) :: :ok
  defp cast(server, message), do: GenServer.cast(server, message)

  defp safe_call(server, message, timeout) do
    GenServer.call(server, message, timeout)
  catch
    :exit, {:noproc, _call} -> {:error, {:runtime_unavailable, :not_found}}
    :exit, {:timeout, _call} -> {:error, {:runtime_unavailable, :timeout}}
    :exit, reason -> {:error, {:runtime_failure, reason}}
  end
end
