defmodule Exdock.Runtime.MutationContract.Nodes do
  @moduledoc false

  alias Exdock.Domain
  alias Exdock.Runtime.Mutation.Payload

  @spec normalize(term(), term()) :: {:ok, term()} | {:error, term()}
  def normalize(:setting, {node, key, value}) when is_binary(node),
    do: normalize(:setting, %Payload.NodeSetting{node: node, key: key, value: value})

  def normalize(:setting, %Payload.NodeSetting{node: node, key: key, value: value})
      when is_binary(node) do
    with {:ok, {key, value}} <- Domain.Node.Settings.validate_setting(key, value) do
      {:ok, %Payload.NodeSetting{node: node, key: key, value: value}}
    end
  end

  def normalize(action, _payload), do: invalid(action)

  defp invalid(action), do: {:error, {:invalid_mutation_payload, :nodes, action}}
end
