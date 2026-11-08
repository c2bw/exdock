defmodule Exdock.Server.Connection.RuntimeBundleProvider do
  @moduledoc """
  Builds the fixed runtime bundle installed by standalone Exdock agents.
  """

  require Logger

  alias Exdock.Protocol.{Compatibility, RuntimeBundle}

  @spec version() :: String.t()
  def version, do: Compatibility.runtime_bundle_version()

  @spec build() :: {:ok, map()} | {:error, :load_module_fail}
  def build do
    with {:ok, modules} <- load_required_modules() do
      {:ok, RuntimeBundle.build(version(), modules)}
    end
  end

  @doc false
  @spec required_modules() :: [module()]
  def required_modules, do: RuntimeBundle.required_modules()

  defp load_required_modules do
    required_modules()
    |> Enum.map(&load_module_binary/1)
    |> collect_loaded_modules()
  end

  defp load_module_binary(module_name) do
    case :code.get_object_code(module_name) do
      {^module_name, binary, filename} -> {module_name, binary, filename}
      :error -> {:error, "Failed to load module: #{module_name}"}
    end
  end

  defp collect_loaded_modules(module_load_results) do
    case Enum.filter(module_load_results, &match?({:error, _}, &1)) do
      [] ->
        {:ok, module_load_results}

      errors ->
        Enum.each(errors, fn {:error, error} ->
          Logger.error("Failed to load runtime module: #{error}")
        end)

        {:error, :load_module_fail}
    end
  end
end
