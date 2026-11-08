defmodule Exdock.ClientLib.UtilsTest do
  use ExUnit.Case, async: true

  alias Exdock.ClientLib.Utils
  alias Exdock.Docker.Error

  test "Docker task streams disable Task's five-second default timeout" do
    assert Utils.async_stream_options() == [timeout: :infinity]
  end

  test "Docker task streams execute each lookup" do
    assert Utils.async_stream([:first, :second], &Atom.to_string/1) |> Enum.to_list() ==
             [{:ok, "first"}, {:ok, "second"}]
  end

  test "does not wrap an already typed Docker error" do
    error = Error.new({:image_pull, :stream}, :timeout)

    assert Utils.docker_error(:image_pull, error) == error
  end
end
