defmodule Exdock.Client.Connection.Metadata do
  @moduledoc """
  Collects stable, display-oriented metadata for the standalone agent.
  """

  @spec collect(String.t()) :: map()
  def collect(agent_version) when is_binary(agent_version) do
    %{
      "platform" => platform(:os.type(), :erlang.system_info(:system_architecture)),
      "agent_version" => agent_version,
      "elixir_version" => System.version(),
      "otp_release" => :erlang.system_info(:otp_release) |> to_string()
    }
  end

  @doc false
  @spec platform({atom(), atom()}, binary() | charlist()) :: String.t()
  def platform(os_type, architecture) do
    "#{normalize_os(os_type)}/#{normalize_architecture(architecture)}"
  end

  defp normalize_os({:unix, :linux}), do: "linux"
  defp normalize_os({:unix, :darwin}), do: "darwin"
  defp normalize_os({:win32, _name}), do: "windows"
  defp normalize_os({_family, name}) when is_atom(name), do: normalize_identifier(Atom.to_string(name))

  defp normalize_architecture(architecture) do
    architecture
    |> to_string()
    |> String.downcase()
    |> String.split("-", parts: 2)
    |> List.first()
    |> canonical_architecture()
  end

  defp canonical_architecture(architecture) when architecture in ["x86_64", "amd64"], do: "amd64"
  defp canonical_architecture(architecture) when architecture in ["i386", "i486", "i586", "i686", "x86"], do: "386"
  defp canonical_architecture(architecture) when architecture in ["aarch64", "arm64"], do: "arm64"
  defp canonical_architecture("armv7" <> _suffix), do: "arm/v7"
  defp canonical_architecture("armv6" <> _suffix), do: "arm/v6"

  defp canonical_architecture(architecture)
       when architecture in ["ppc64le", "riscv64", "s390x"],
       do: architecture

  defp canonical_architecture(architecture), do: normalize_identifier(architecture)

  defp normalize_identifier(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "unknown"
      normalized -> normalized
    end
  end
end
