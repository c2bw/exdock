defmodule Exdock.Server.State.Storage.Persistence.ErrorTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.State.Storage.Persistence.Error

  test "retains the operation and original cause until a presentation boundary" do
    cause = {:constraint, :unique, %{field: :name}}
    error = Error.new(:container_insert, cause)

    assert error == %Error{operation: :container_insert, cause: cause}

    assert Error.format(error) ==
             "db_error: container_insert: {:constraint, :unique, %{field: :name}}"
  end
end
