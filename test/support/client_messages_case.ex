defmodule Exdock.Server.State.ClientMessagesCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      import Exdock.Server.State.ClientMessagesFixtures
      import Exdock.Server.State.ClientMessagesCase, only: [commit_client_message: 2, commit_client_message: 3]
    end
  end

  setup tags do
    Exdock.DataCase.setup_sandbox(tags)

    unless Process.whereis(Exdock.Database.Vault) do
      start_supervised!({Exdock.Database.Vault, name: Exdock.Database.Vault})
    end

    :ok
  end

  def commit_client_message(state, message, occurred_at \\ DateTime.utc_now()) do
    Exdock.Server.State.ClientMessages.commit(
      state,
      message,
      occurred_at,
      effect_runner: &capture_effects/2
    )
  end

  defp capture_effects(_state, effects) do
    Enum.each(effects, &capture_effect/1)
    :ok
  end

  defp capture_effect({:job_info, message}), do: send(self(), {:captured, {:job_info_message, message}})
  defp capture_effect({:job_update, update}), do: send(self(), {:captured, {:job_update, update}})
  defp capture_effect({:job_result, result}), do: send(self(), {:captured, {:job_result, result}})

  defp capture_effect({:server_command, command, opts}) do
    send(self(), {:captured_info, {:delayed_command, nil, command, opts}})
  end

  defp capture_effect(_effect), do: :ok
end
