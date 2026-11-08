defmodule Exdock.AgentRuntime.Wire do
  @moduledoc """
  Converts Docker refresh snapshots into protocol-owned map shapes.

  The server reconstructs its internal client snapshot structures only after
  validating the authenticated protocol-v4 result.
  """

  alias Exdock.Protocol.Snapshot.{Container, Image}
  alias Exdock.Protocol.Value

  @docker_error_module :"Elixir.Exdock.Docker.Error"

  @spec encode_result(String.t(), term()) :: term()
  def encode_result("node_refresh", {containers, images}) do
    %{
      "containers" => encode_result_set(containers, &encode_container/1),
      "images" => encode_result_set(images, &encode_image/1)
    }
  end

  # Worker failures can have no snapshot data; keep the result decodable so
  # the server receives the terminal error instead of losing the dispatcher.
  def encode_result("node_refresh", nil),
    do: encode_result("node_refresh", {%{ok: [], errored: []}, %{ok: [], errored: []}})

  def encode_result("container_resources", sample), do: Value.encode(sample)
  def encode_result(_kind, data), do: data

  @doc "Encodes a command failure without exposing client-runtime structs."
  @spec encode_error(term()) :: term()
  def encode_error(%{__struct__: module, message: message})
      when module == @docker_error_module and is_binary(message),
      do: message

  def encode_error(error), do: error

  defp encode_result_set(%{ok: values, errored: errors}, encoder)
       when is_list(values) and is_list(errors) do
    %{
      "ok" => Enum.map(values, encoder),
      "errored" => Enum.map(errors, &encode_error(&1, encoder))
    }
  end

  defp encode_container(%Container{} = container), do: Container.to_wire(container)

  defp encode_image(%Image{} = image), do: Image.to_wire(image)

  defp encode_error({error, %Container{} = container}, _encoder),
    do: {encode_error(error), encode_container(container)}

  defp encode_error({error, %Image{} = image}, _encoder),
    do: {encode_error(error), encode_image(image)}

  defp encode_error(error, _encoder), do: error |> encode_error() |> Value.encode()
end
