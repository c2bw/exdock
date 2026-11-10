defmodule Exdock.Client.Connection.MetadataTest do
  use ExUnit.Case, async: true

  alias Exdock.Client.Connection.Metadata

  test "normalizes common Docker platform architectures" do
    assert Metadata.platform({:unix, :linux}, "x86_64-pc-linux-gnu") == "linux/amd64"
    assert Metadata.platform({:unix, :linux}, "i686-pc-linux-gnu") == "linux/386"
    assert Metadata.platform({:unix, :linux}, "aarch64-unknown-linux-gnu") == "linux/arm64"
    assert Metadata.platform({:unix, :linux}, "armv7l-unknown-linux-gnueabihf") == "linux/arm/v7"
    assert Metadata.platform({:unix, :linux}, "armv6l-unknown-linux-gnueabihf") == "linux/arm/v6"
    assert Metadata.platform({:unix, :linux}, "ppc64le-unknown-linux-gnu") == "linux/ppc64le"
    assert Metadata.platform({:unix, :linux}, "riscv64-unknown-linux-gnu") == "linux/riscv64"
    assert Metadata.platform({:unix, :linux}, "s390x-ibm-linux-gnu") == "linux/s390x"
  end

  test "normalizes known operating systems and safely falls back for unknown values" do
    assert Metadata.platform({:unix, :darwin}, "arm64-apple-darwin") == "darwin/arm64"
    assert Metadata.platform({:win32, :nt}, "x86_64-pc-windows") == "windows/amd64"
    assert Metadata.platform({:unix, :plan_9}, "Mystery CPU!") == "plan_9/mystery-cpu"
  end

  test "collects all required metadata fields" do
    assert %{
             "platform" => platform,
             "agent_version" => "1.2.0",
             "elixir_version" => elixir_version,
             "otp_release" => otp_release
           } = Metadata.collect("1.2.0")

    assert is_binary(platform) and platform != ""
    assert elixir_version == System.version()
    assert is_binary(otp_release) and otp_release != ""
  end
end
