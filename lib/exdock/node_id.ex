defmodule Exdock.NodeId do
  @moduledoc """
  Canonical contract for node identifiers used across Exdock.

  Node identifiers remain validated strings at transport, runtime, persistence,
  and presentation boundaries. This module deliberately never converts
  external or persisted values to atoms.
  """

  @reserved_names MapSet.new(["local"])
  @max_length 64
  @name_pattern ~r/^[A-Za-z0-9][A-Za-z0-9_.-]*$/

  @type t :: String.t()
  @type invalid_reason :: :empty | :too_long | :reserved | :invalid_format
  @type normalize_error :: invalid_reason() | :invalid_type

  @spec validate(term()) :: :ok | {:error, invalid_reason()}
  def validate(name) when is_binary(name) do
    cond do
      name == "" -> {:error, :empty}
      String.length(name) > @max_length -> {:error, :too_long}
      MapSet.member?(@reserved_names, name) -> {:error, :reserved}
      not Regex.match?(@name_pattern, name) -> {:error, :invalid_format}
      true -> :ok
    end
  end

  def validate(_name), do: {:error, :invalid_format}

  @spec valid?(term()) :: boolean()
  def valid?(name), do: validate(name) == :ok

  @spec normalize(term()) :: {:ok, t()} | {:error, normalize_error()}
  def normalize(name) when is_binary(name) do
    case validate(name) do
      :ok -> {:ok, name}
      {:error, reason} -> {:error, reason}
    end
  end

  def normalize(_name), do: {:error, :invalid_type}

  @spec normalize!(term()) :: t()
  def normalize!(name) do
    case normalize(name) do
      {:ok, node} -> node
      {:error, reason} -> raise ArgumentError, "invalid node name #{inspect(name)}: #{reason}"
    end
  end
end
