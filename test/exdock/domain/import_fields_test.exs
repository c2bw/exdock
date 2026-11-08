defmodule Exdock.Domain.ImportFieldsTest do
  use ExUnit.Case, async: true

  alias Exdock.Domain.ImportFields
  alias Exdock.Domain.ImportFieldsTest.Example

  test "applies only known fields with valid values" do
    fields = [
      {"enabled", :enabled, &is_boolean/1},
      {"label", :label, &is_binary/1}
    ]

    unsafe = %{
      "enabled" => true,
      "label" => 42,
      "unknown_field" => "ignored"
    }

    assert %Example{enabled: true, label: "default"} =
             ImportFields.apply_fields(%Example{}, unsafe, fields, &set/3)
  end

  test "keeps false boolean values when they are valid" do
    fields = [
      {"enabled", :enabled, &is_boolean/1}
    ]

    unsafe = %{"enabled" => false}

    assert %Example{enabled: false, label: "default"} =
             ImportFields.apply_fields(%Example{}, unsafe, fields, &set/3)
  end

  defp set(%Example{} = settings, field, value), do: Map.replace!(settings, field, value)
end
