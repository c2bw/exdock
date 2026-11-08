defmodule Exdock.Protocol.RuntimeBundle do
  @moduledoc """
  Builds and validates versioned hot-loaded agent runtime bundles.

  The digest covers module names and bytecode, independent of build-machine file
  paths. Namespace policy remains a client responsibility and is supplied as a
  predicate during validation.
  """

  @required_modules [
    Exdock.AgentRuntime,
    Exdock.AgentRuntime.Executor,
    Exdock.AgentRuntime.Size,
    Exdock.AgentRuntime.Wire
  ]

  @type module_entry :: {module(), binary(), binary() | charlist()}
  @type t :: %{required(String.t()) => term()}

  @spec required_modules() :: [module()]
  def required_modules, do: @required_modules

  @spec build(String.t(), [module_entry()]) :: t()
  def build(version, modules) when is_binary(version) and is_list(modules) do
    %{"version" => version, "digest" => digest(modules), "modules" => modules}
  end

  @spec validate(term(), (module() -> boolean())) :: :ok | {:error, term()}
  def validate(%{"version" => version, "digest" => digest, "modules" => modules}, allowed_module?)
      when is_binary(version) and is_binary(digest) and is_list(modules) and is_function(allowed_module?, 1) do
    with :ok <- validate_entries(modules, allowed_module?),
         :ok <- validate_module_set(modules),
         true <- digest(modules) == digest do
      :ok
    else
      false -> {:error, :digest_mismatch}
      {:error, _reason} = error -> error
    end
  end

  def validate(_bundle, _allowed_module?), do: {:error, :invalid_bundle}

  @spec digest([module_entry()]) :: String.t()
  def digest(modules) when is_list(modules) do
    modules
    |> Enum.map(fn {module, binary, _filename} -> {Atom.to_string(module), binary} end)
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp validate_entries(modules, allowed_module?) do
    Enum.reduce_while(modules, :ok, fn
      {module, binary, filename}, :ok
      when is_atom(module) and is_binary(binary) and (is_binary(filename) or is_list(filename)) ->
        if allowed_module?.(module), do: {:cont, :ok}, else: {:halt, {:error, {:module_not_allowed, module}}}

      _entry, :ok ->
        {:halt, {:error, :invalid_module_entry}}
    end)
  end

  defp validate_module_set(modules) do
    supplied_modules = Enum.map(modules, &elem(&1, 0))

    case duplicate_module(supplied_modules) do
      nil ->
        required = MapSet.new(@required_modules)
        supplied = MapSet.new(supplied_modules)
        missing = required |> MapSet.difference(supplied) |> Enum.sort()
        unexpected = supplied |> MapSet.difference(required) |> Enum.sort()

        if missing == [] and unexpected == [],
          do: :ok,
          else: {:error, {:runtime_module_set_mismatch, missing, unexpected}}

      module ->
        {:error, {:duplicate_runtime_module, module}}
    end
  end

  defp duplicate_module(modules) do
    Enum.reduce_while(modules, MapSet.new(), fn module, seen ->
      if MapSet.member?(seen, module),
        do: {:halt, module},
        else: {:cont, MapSet.put(seen, module)}
    end)
    |> case do
      %MapSet{} -> nil
      module -> module
    end
  end
end
