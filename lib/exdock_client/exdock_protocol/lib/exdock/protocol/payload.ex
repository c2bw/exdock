defmodule Exdock.Protocol.Payload do
  @moduledoc "Adapts Exdock domain values to the shared NodeWire message schema."

  alias Exdock.Protocol.{RuntimeBundle, Value}

  @modules RuntimeBundle.required_modules()
  @errors ~w(invalid_auth duplicate_name invalid_name load_module_fail runtime_bundle_mismatch
             unauthorized unexpected_message malformed_message client_job_timeout shutdown)a
  @log_options ~w(stdout stderr since until timestamps tail follow)a
  @binary_chunk 524_288

  def encode(:runtime_bundle, %{"modules" => modules} = bundle) when is_list(modules) do
    with :ok <- RuntimeBundle.validate(bundle, &(&1 in @modules)) do
      encoded = Map.new(modules, fn {module, bytes, _filename} -> {Atom.to_string(module), bytes} end)
      {:ok, %{bundle | "modules" => encoded}}
    end
  end

  def encode(:error, {:version_requirement, requirement}) when is_binary(requirement),
    do: {:ok, %{"reason" => "version_requirement", "requirement" => requirement}}

  def encode(:error, reason) when is_atom(reason), do: {:ok, %{"reason" => Atom.to_string(reason)}}

  def encode(:error, _reason), do: {:ok, %{"reason" => "connection_error"}}

  def encode(:command, %{"kind" => "container_logs", "args" => [id, opts]} = payload) do
    if Keyword.keyword?(opts) and Enum.all?(opts, fn {key, _value} -> key in @log_options end) do
      {:ok, %{payload | "args" => [id, Enum.map(opts, fn {key, value} -> [Atom.to_string(key), value] end)]}}
    else
      {:error, :invalid_log_options}
    end
  end

  def encode(:result, %{"kind" => "container_logs", "data" => {id, lines}} = payload)
      when is_binary(id) and is_list(lines) do
    if Enum.all?(lines, &is_binary/1) do
      {:ok,
       %{
         payload
         | "data" => %{"container_id" => id, "lines" => Enum.map(lines, &encode_binary/1)},
           "error" => json_value(payload["error"])
       }}
    else
      {:error, :invalid_logs}
    end
  end

  def encode(:result, %{"kind" => "node_refresh", "data" => data, "error" => error} = payload) do
    with {:ok, data} <- encode_refresh(data) do
      {:ok, %{payload | "data" => data, "error" => json_value(error)}}
    end
  end

  def encode(_name, payload) when is_map(payload), do: {:ok, json_value(payload)}
  def encode(_name, _payload), do: {:error, :invalid_payload}

  def decode(:runtime_bundle, %{"modules" => modules} = bundle) when map_size(modules) == length(@modules) do
    entries =
      Enum.map(@modules, fn module ->
        name = Atom.to_string(module)
        {module, modules[name], String.to_charlist(name <> ".beam")}
      end)

    bundle = %{bundle | "modules" => entries}

    with :ok <- RuntimeBundle.validate(bundle, &(&1 in @modules)), do: {:ok, bundle}
  end

  def decode(:runtime_bundle, _payload), do: {:error, :invalid_runtime_bundle}

  def decode(:error, %{"reason" => "version_requirement", "requirement" => requirement}),
    do: {:ok, {:version_requirement, requirement}}

  def decode(:error, %{"reason" => reason}),
    do: {:ok, Enum.find(@errors, :connection_error, &(Atom.to_string(&1) == reason))}

  def decode(:command, %{"kind" => "container_logs", "args" => [id, opts]} = payload) when is_list(opts) do
    with {:ok, opts} <- traverse(opts, &decode_log_option/1), do: {:ok, %{payload | "args" => [id, opts]}}
  end

  def decode(:command, %{"kind" => "container_logs", "args" => [_, _]}), do: {:error, :invalid_log_options}

  def decode(:result, %{"kind" => "container_logs", "data" => %{"container_id" => id, "lines" => lines}} = payload)
      when is_binary(id) and is_list(lines) do
    with {:ok, lines} <- traverse(lines, &decode_binary/1), do: {:ok, %{payload | "data" => {id, lines}}}
  end

  def decode(:result, %{"kind" => "container_logs", "data" => nil, "error" => error} = payload)
      when not is_nil(error),
      do: {:ok, payload}

  def decode(:result, %{"kind" => "container_logs"}), do: {:error, :invalid_logs}

  def decode(:result, %{"kind" => "node_refresh", "data" => data} = payload) do
    with {:ok, data} <- decode_refresh(data) do
      {:ok, %{payload | "data" => data}}
    end
  end

  def decode(_name, payload), do: {:ok, payload}

  defp json_value(value), do: normalize_json(Value.encode(value))

  defp normalize_json(value) do
    case value do
      map when is_map(map) -> Map.new(map, fn {key, entry} -> {key, normalize_json(entry)} end)
      list when is_list(list) -> Enum.map(list, &normalize_json/1)
      tuple when is_tuple(tuple) -> tuple |> Tuple.to_list() |> Enum.map(&normalize_json/1)
      atom when is_atom(atom) and atom not in [true, false, nil] -> Atom.to_string(atom)
      bytes when is_binary(bytes) -> if String.valid?(bytes), do: bytes, else: inspect(bytes)
      other -> other
    end
  end

  # Apply the JSON parser's structural limits to each inspection independently.
  # The outer NodeWire frame still limits the total bytes and record count.
  defp encode_refresh(data), do: map_refresh_sets(data, &encode_result_set/1)
  defp decode_refresh(data), do: map_refresh_sets(data, &decode_result_set/1)

  defp map_refresh_sets(%{"containers" => containers, "images" => images}, mapper) do
    with {:ok, containers} <- mapper.(containers),
         {:ok, images} <- mapper.(images) do
      {:ok, %{"containers" => containers, "images" => images}}
    end
  end

  defp map_refresh_sets(_data, _mapper), do: {:error, :invalid_refresh_payload}

  defp encode_result_set(%{"ok" => values, "errored" => errors}) when is_list(values) and is_list(errors) do
    errors =
      Enum.map(errors, fn
        {error, snapshot} when is_map(snapshot) -> %{"error" => error, "snapshot" => snapshot}
        error -> %{"error" => error}
      end)

    with {:ok, values} <- traverse(values, &encode_snapshot/1),
         {:ok, errors} <- traverse(errors, &encode_snapshot/1) do
      {:ok, %{"ok" => values, "errored" => errors}}
    end
  end

  defp encode_result_set(_set), do: {:error, :invalid_refresh_payload}

  defp decode_result_set(%{"ok" => values, "errored" => errors}) when is_list(values) and is_list(errors) do
    with {:ok, values} <- traverse(values, &decode_snapshot/1),
         {:ok, errors} <- traverse(errors, &decode_snapshot_error/1) do
      {:ok, %{"ok" => values, "errored" => errors}}
    end
  end

  defp decode_result_set(_set), do: {:error, :invalid_refresh_payload}

  defp encode_snapshot(snapshot) when is_map(snapshot) do
    snapshot = json_value(snapshot)
    with :ok <- NodeWire.Schema.bounds(snapshot), do: {:ok, JSON.encode!(snapshot)}
  end

  defp encode_snapshot(_snapshot), do: {:error, :invalid_refresh_payload}

  defp decode_snapshot(snapshot) when is_binary(snapshot) do
    with {:ok, value} <- NodeWire.JSON.decode(snapshot),
         :ok <- NodeWire.Schema.bounds(value) do
      {:ok, value}
    end
  end

  defp decode_snapshot(_snapshot), do: {:error, :invalid_refresh_payload}

  defp decode_snapshot_error(snapshot) do
    case decode_snapshot(snapshot) do
      {:ok, %{"error" => error, "snapshot" => snapshot}} when is_map(snapshot) -> {:ok, {error, snapshot}}
      {:ok, %{"error" => error}} -> {:ok, error}
      {:ok, _snapshot} -> {:error, :invalid_refresh_payload}
      {:error, _reason} = error -> error
    end
  end

  defp decode_log_option([key, value]) do
    case Enum.find(@log_options, &(Atom.to_string(&1) == key)) do
      nil -> {:error, :invalid_log_options}
      option -> {:ok, {option, value}}
    end
  end

  defp decode_log_option(_), do: {:error, :invalid_log_options}

  defp encode_binary(<<chunk::binary-size(@binary_chunk), rest::binary>>),
    do: [Base.encode64(chunk) | encode_binary(rest)]

  defp encode_binary(<<>>), do: []
  defp encode_binary(bytes), do: [Base.encode64(bytes)]

  defp decode_binary(chunks) when is_list(chunks) do
    with {:ok, chunks} <- traverse(chunks, &decode_chunk/1), do: {:ok, IO.iodata_to_binary(chunks)}
  end

  defp decode_binary(_), do: {:error, :invalid_logs}

  defp decode_chunk(chunk) when is_binary(chunk) do
    case Base.decode64(chunk) do
      {:ok, bytes} when byte_size(bytes) <= @binary_chunk -> {:ok, bytes}
      _ -> {:error, :invalid_logs}
    end
  end

  defp decode_chunk(_), do: {:error, :invalid_logs}

  defp traverse(values, fun) do
    values
    |> Enum.reduce_while([], fn value, acc ->
      case fun.(value) do
        {:ok, value} -> {:cont, [value | acc]}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:error, _reason} = error -> error
      values -> {:ok, Enum.reverse(values)}
    end
  end
end
