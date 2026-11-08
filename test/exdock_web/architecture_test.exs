defmodule ExdockWeb.ArchitectureTest do
  use ExUnit.Case, async: true

  test "compiled web modules depend on public application boundaries" do
    assert_no_references(application_modules("ExdockWeb"), [
      "Exdock.Server",
      "Exdock.Database"
    ])
  end

  test "runtime commands do not depend on transport implementations" do
    assert_no_references(application_modules("Exdock.Runtime"), [
      "Exdock.Server.Connection",
      "Exdock.Database"
    ])
  end

  test "runtime queries do not synchronously depend on activity processes" do
    assert_no_references([Exdock.Runtime.Query], [
      {:exact, "Exdock.Server.Logging"},
      {:exact, "GenServer"}
    ])
  end

  test "read-model projections do not depend on authoritative state storage" do
    assert_no_references(application_modules("Exdock.ReadModel.Projections"), [
      "Exdock.Server.State",
      "Exdock.Database"
    ])
  end

  test "domain types do not depend on server or database implementation modules" do
    assert_no_references(application_modules("Exdock.Domain"), [
      "Exdock.Server",
      "Exdock.Database"
    ])
  end

  test "logging status transitions remain free of process and persistence effects" do
    assert_no_references(application_modules("Exdock.Server.Logging.Status"), [
      {:exact, "Exdock.Server.Jobs"},
      {:exact, "Exdock.Server.Notifier"},
      {:exact, "Exdock.Repo"},
      {:exact, "GenServer"},
      {:exact, "Process"}
    ])
  end

  test "canonical public types do not regress to compatibility namespaces" do
    assert_no_references(application_modules(), [
      "Exdock.Server.Connection.NodeName",
      "Exdock.Server.Settings.ServerConfiguration",
      "Exdock.Server.State.Storage.Structures"
    ])
  end

  defp application_modules(prefix \\ nil) do
    modules =
      :exdock
      |> Application.spec(:modules)
      |> Kernel.||([])
      |> Enum.filter(&application_source?/1)

    if prefix do
      Enum.filter(modules, &namespace?(module_name(&1), prefix))
    else
      modules
    end
  end

  defp assert_no_references(modules, forbidden_namespaces) do
    assert modules != [], "architecture check did not discover any application modules"

    violations =
      for module <- modules,
          reference <- module_references(module),
          forbidden <- forbidden_namespaces,
          forbidden_reference?(module_name(reference), forbidden),
          do: "#{module_name(module)} -> #{module_name(reference)}"

    assert violations == [],
           "architecture boundary violations:\n#{violations |> Enum.uniq() |> Enum.sort() |> Enum.join("\n")}"
  end

  defp module_references(module) do
    case :beam_lib.chunks(application_beam(module), [:abstract_code]) do
      {:ok, {^module, abstract_code: {:raw_abstract_v1, forms}}} ->
        collect_atoms(forms, MapSet.new())

      {:ok, {^module, abstract_code: :no_abstract_code}} ->
        raise "missing abstract code for #{module_name(module)}"
    end
  end

  defp application_beam(module) do
    :exdock
    |> Application.app_dir("ebin")
    |> Path.join("#{module}.beam")
    |> String.to_charlist()
  end

  defp collect_atoms(value, atoms) when is_atom(value), do: MapSet.put(atoms, value)

  defp collect_atoms(value, atoms) when is_list(value) do
    Enum.reduce(value, atoms, &collect_atoms/2)
  end

  defp collect_atoms(value, atoms) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> collect_atoms(atoms)
  end

  defp collect_atoms(value, atoms) when is_map(value) do
    Enum.reduce(value, atoms, fn {key, map_value}, acc ->
      acc
      |> collect_atoms(key)
      |> collect_atoms(map_value)
    end)
  end

  defp collect_atoms(_value, atoms), do: atoms

  defp application_source?(module) do
    with {:module, ^module} <- Code.ensure_loaded(module),
         source when is_list(source) <- module.module_info(:compile)[:source] do
      source
      |> List.to_string()
      |> Path.relative_to_cwd()
      |> String.starts_with?("lib/")
    else
      _missing_source -> false
    end
  end

  defp forbidden_reference?(module, {:exact, forbidden}), do: module == forbidden
  defp forbidden_reference?(module, forbidden), do: namespace?(module, forbidden)

  defp namespace?(module, namespace),
    do: module == namespace or String.starts_with?(module, namespace <> ".")

  defp module_name(module) when is_atom(module), do: inspect(module)
end
