defmodule Exdock.Server.Connection.Protocol do
  @moduledoc """
  Server codec for the NodeWire agent contract.

  All payloads are validated protocol-owned maps or wire DTOs. Translation to
  server job and state messages happens outside this codec, so no server struct
  crosses or is required by the transport boundary.
  """

  alias Exdock.Protocol.Snapshot.{Container, Image}
  alias Exdock.Protocol.{AgentMetadata, Contract, Message, Payload}
  alias Exdock.NodeId
  alias Exdock.Server.Connection.WireMessage

  @type trust :: :untrusted | :authenticated

  def encode_message({:command, command}) do
    if Message.valid_command?(command), do: Contract.encode!(:command, command), else: raise(ArgumentError, "invalid command")
  end

  def encode_message({name, payload}) when name in [:error, :runtime_bundle], do: Contract.encode!(name, payload)

  def decode_message(frame, trust \\ :untrusted) do
    case Contract.decode(frame) do
      {:ok, message} -> decode_event(message, trust)
      {:error, _} -> {:error, :malformed_message}
    end
  end

  def decode_event({name, payload}, trust) do
    with {:ok, payload} <- Payload.decode(name, payload) do
      decode_payload(name, payload, trust)
    else
      {:error, _} -> {:error, :malformed_message}
    end
  end

  defp decode_payload(:error, reason, _trust), do: {:error, reason}

  defp decode_payload(:hello, %{"agent_version" => version, "auth_token" => token, "node" => node}, :untrusted),
    do: {:hello, version, token, node}

  defp decode_payload(:ready, %{"bundle_version" => version, "digest" => digest, "metadata" => metadata}, :authenticated) do
    case AgentMetadata.sanitize(metadata) do
      {:ok, metadata} -> {:ready, version, digest, metadata}
      {:error, :invalid_metadata} -> {:error, :malformed_message}
    end
  end

  defp decode_payload(:progress, payload, :authenticated) do
    with true <- Message.valid_progress?(payload),
         {:ok, message} <- progress_message(payload) do
      {:client_message, message}
    else
      _ -> {:error, :malformed_message}
    end
  end

  defp decode_payload(:result, payload, :authenticated) do
    with true <- Message.valid_result?(payload),
         {:ok, message} <- result_message(payload) do
      {:client_message, message}
    else
      _ -> {:error, :malformed_message}
    end
  end

  defp decode_payload(:resource_sample, payload, :authenticated) do
    with true <- Message.valid_resource_sample?(payload),
         {:ok, message} <- resource_message(payload) do
      {:client_message, message}
    else
      _ -> {:error, :malformed_message}
    end
  end

  defp decode_payload(_name, _payload, _trust), do: {:error, :malformed_message}

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
end
