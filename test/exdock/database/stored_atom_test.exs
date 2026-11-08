defmodule Exdock.Database.StoredAtomTest do
  use ExUnit.Case, async: true

  alias Exdock.Database.StoredAtom

  test "dumps atoms to database strings" do
    assert StoredAtom.dump(:passthrough) == "passthrough"
  end

  test "loads only explicitly allowed atoms" do
    allowed = [:enabled, :disabled, :passthrough]

    assert StoredAtom.load("enabled", allowed, :passthrough) == :enabled
    assert StoredAtom.load(:disabled, allowed, :passthrough) == :disabled
    assert StoredAtom.load("surprise", allowed, :passthrough) == :passthrough
    assert StoredAtom.load(nil, allowed, :passthrough) == :passthrough
  end
end
