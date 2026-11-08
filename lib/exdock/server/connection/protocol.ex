defmodule Exdock.Server.Connection.Protocol do
  @moduledoc """
  Server codec for the explicit protocol-v4 agent contract.

  All payloads are validated protocol-owned maps or wire DTOs. Translation to
  server job and state messages happens outside this codec, so no server struct
  crosses or is required by the transport boundary.
  """

  alias Exdock.Protocol.Snapshot.{Container, Image}
  alias Exdock.Protocol.{AgentMetadata, Contract, Envelope, Message}
  alias Exdock.NodeId
  alias Exdock.Server.Connection.WireMessage

  @type trust :: :untrusted | :authenticated

  def encode_message({:heartbeat}), do: Contract.encode_frame(:heartbeat, "")
  def encode_message({:error, reason}), do: encode_term(:error, reason)
  def encode_message({:runtime_bundle, bundle}) when is_map(bundle), do: encode_term(:runtime_bundle, bundle)

  def encode_message({:command, command}) when is_map(command) do
    if Message.valid_command?(command) do
      encode_term(:command, command)
    else
      raise ArgumentError, "invalid agent command payload: #{inspect(command)}"
    end
  end

  @spec decode_message(binary(), trust()) :: tuple()
  def decode_message(frame, trust \\ :untrusted)

  def decode_message(frame, trust) when is_binary(frame) and trust in [:untrusted, :authenticated] do
    Envelope.decode(frame, &decode_payload(&1, &2, trust))
  end

  def decode_message(_frame, _trust), do: {:error, :malformed_message}

  defp decode_payload(:heartbeat, payload, _trust), do: {:ok, {:heartbeat, payload}}
  defp decode_payload(:error, payload, _trust), do: Envelope.decode_term(payload, &{:ok, {:error, &1}})

  defp decode_payload(:hello, payload, :untrusted) do
    Envelope.decode_term(payload, fn
      %{"agent_version" => version, "auth_token" => token, "node" => node}
      when is_binary(version) and is_binary(token) and is_binary(node) ->
        {:ok, {:hello, version, token, node}}

      _payload ->
        {:error, :malformed_message}
    end)
  end

  defp decode_payload(:ready, payload, :authenticated) do
    Envelope.decode_term(payload, fn
      %{"bundle_version" => version, "digest" => digest, "metadata" => metadata}
      when is_binary(version) and is_binary(digest) ->
        case AgentMetadata.sanitize(metadata) do
          {:ok, metadata} -> {:ok, {:ready, version, digest, metadata}}
          {:error, :invalid_metadata} -> {:error, :malformed_message}
        end

      _payload ->
        {:error, :malformed_message}
    end)
  end

  defp decode_payload(:progress, payload, :authenticated) do
    Envelope.decode_term(payload, fn payload ->
      with true <- Message.valid_progress?(payload),
           {:ok, message} <- progress_message(payload) do
        {:ok, {:client_message, message}}
      else
        _invalid -> {:error, :malformed_message}
      end
    end)
  end

  defp decode_payload(:result, payload, :authenticated) do
    Envelope.decode_term(payload, fn payload ->
      with true <- Message.valid_result?(payload),
           {:ok, message} <- result_message(payload) do
        {:ok, {:client_message, message}}
      else
        _ -> {:error, :malformed_message}
      end
    end)
  end

  defp decode_payload(:resource_sample, payload, :authenticated) do
    Envelope.decode_term(payload, fn payload ->
      with true <- Message.valid_resource_sample?(payload),
           {:ok, message} <- resource_message(payload) do
        {:ok, {:client_message, message}}
      else
        _invalid -> {:error, :malformed_message}
      end
    end)
  end

  defp decode_payload(_message_type, _payload, _trust), do: {:error, :malformed_message}

  defp progress_message(%{"id" => id, "kind" => kind, "node" => node, "data" => data}) do
    with {:ok, node} <- NodeId.normalize(node) do
      {:ok, WireMessage.progress(id, kind, node, data)}
    end
  end

  defp result_message(%{"id" => id, "kind" => kind, "node" => node, "data" => data, "error" => error}) do
    with {:ok, node} <- NodeId.normalize(node),
         {:ok, decoded_data} <- decode_result_data(kind, data) do
      {:ok, WireMessage.result(id, kind, node, decoded_data, error)}
    end
  end

  defp decode_result_data("node_refresh", %{"containers" => containers, "images" => images}) do
    with {:ok, containers} <- decode_result_set(containers, &Container.from_wire/1),
         {:ok, images} <- decode_result_set(images, &Image.from_wire/1) do
      {:ok, {containers, images}}
    else
      _invalid -> {:error, :invalid_node_refresh_result}
    end
  end

  defp decode_result_data("node_refresh", _data), do: {:error, :invalid_node_refresh_result}
  defp decode_result_data(_kind, data), do: {:ok, data}

  defp decode_result_set(%{"ok" => values, "errored" => errors}, decoder)
       when is_list(values) and is_list(errors) do
    with {:ok, values} <- decode_values(values, decoder),
         {:ok, errors} <- decode_values(errors, &decode_error(&1, decoder)) do
      {:ok, %{ok: values, errored: errors}}
    end
  end

  defp decode_result_set(_payload, _decoder), do: {:error, :invalid_result_set}

  defp decode_values(values, decoder) do
    Exdock.Result.traverse(values, decoder)
  end

  defp decode_error({error, value}, decoder) when is_map(value),
    do: decoder.(value) |> map_decoded_error(error)

  defp decode_error(error, _decoder), do: {:ok, error}

  defp resource_message(%{"node" => node, "container_id" => id, "sample" => sample}) do
    with {:ok, node} <- NodeId.normalize(node) do
      {:ok, WireMessage.resource_sample(node, id, sample)}
    end
  end

  defp map_decoded_error({:ok, value}, error), do: {:ok, {error, value}}
  defp map_decoded_error({:error, _reason} = result, _error), do: result

  defp encode_term(message_type, payload), do: Contract.encode_term_frame(message_type, payload)
end
