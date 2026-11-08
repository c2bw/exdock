defmodule Exdock.Server.State.Storage.Persistence.PersistedStructTest do
  use ExUnit.Case, async: true

  alias Exdock.Domain.Container.Configuration
  alias Exdock.Server.State.Storage.Persistence.PersistedStruct

  test "decodes mixed persistence keys using only known struct fields" do
    attributes = %{
      :hostname => "atom value",
      "hostname" => "string value",
      "binds" => ["source:/target"],
      "unknown" => "ignored"
    }

    assert %Configuration{hostname: "string value", binds: ["source:/target"]} =
             PersistedStruct.decode(attributes, Configuration)
  end
end
