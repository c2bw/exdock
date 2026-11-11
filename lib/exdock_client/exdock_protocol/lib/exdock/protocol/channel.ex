defmodule Exdock.Protocol.Channel do
  @moduledoc "Runs the NodeWire reducer and writes transport effects in order."

  alias Exdock.Protocol.{NodeWire, Payload}
  alias Elixir.NodeWire.Session

  @agent_messages [:hello, :ready, :progress, :result, :resource_sample, :error]
  @server_messages [:runtime_bundle, :command, :error]
  @tick_interval 500

  def tick_interval, do: @tick_interval

  def start(role, write, max_frame_bytes \\ 8_388_626) do
    {inbound, outbound} =
      case role do
        :server -> {@agent_messages, @server_messages}
        :client -> {@server_messages, @agent_messages}
      end

    with {:ok, session} <-
           Session.new(
             role: role,
             protocols: [NodeWire],
             inbound_messages: inbound,
             outbound_messages: outbound,
             max_frame_bytes: max_frame_bytes
           ) do
      session |> Session.start(now()) |> apply_effects(write)
    end
  end

  def feed(session, bytes, write), do: session |> Session.feed(bytes, now()) |> apply_effects(write)
  def tick(session, write), do: session |> Session.tick(now()) |> apply_effects(write)

  def send_event(session, {name, payload}, write) do
    with {:ok, payload} <- Payload.encode(name, payload) do
      case Session.send_event(session, name, payload, now(), ack: false) do
        {:ok, nil, session, effects} -> apply_effects({:ok, session, effects}, write)
        {:error, %Session.Error{code: :invalid_payload}} = error -> encoding_error(name, payload, error)
        {:error, _reason} = error -> error
      end
    end
  end

  defp encoding_error(name, payload, error) do
    case NodeWire.encode(name, payload) do
      {:ok, _frame} -> error
      {:error, _reason} = error -> error
    end
  end

  defp apply_effects({:ok, session, effects}, write) do
    effects
    |> Enum.reduce_while([], fn
      {:send, bytes}, events ->
        case write.(bytes) do
          :ok -> {:cont, events}
          {:error, reason} -> {:halt, {:error, {:transport_error, reason}}}
        end

      {:close_transport, reason}, _events ->
        {:halt, {:error, reason}}

      {:established, _}, events ->
        {:cont, [:established | events]}

      {:event, name, payload}, events ->
        {:cont, [{name, payload} | events]}

      _, _events ->
        {:halt, {:error, :unexpected_session_effect}}
    end)
    |> case do
      {:error, reason} ->
        Session.close(session, reason)
        {:error, reason}

      events ->
        {:ok, session, Enum.reverse(events)}
    end
  end

  defp apply_effects({:error, _reason} = error, _write), do: error

  defp now, do: System.monotonic_time(:millisecond)
end
