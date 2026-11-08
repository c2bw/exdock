defmodule Exdock.TestSupport.BlockingCommandExecutor do
  @moduledoc false

  def execute(%{"id" => id, "test_owner" => owner, "args" => [target | _]}) do
    send(owner, {:command_started, id, self()})

    receive do
      :complete -> {:ok, target}
      :fail -> {:error, :injected_failure, target}
    end
  end
end
