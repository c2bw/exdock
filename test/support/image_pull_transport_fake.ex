defmodule Exdock.Docker.Local.ImagePullTransportFake do
  @moduledoc false

  @behaviour Exdock.Docker.Local.Image.PullTransport

  @impl true
  def stream(%{owner: owner, outcome: outcome}, image_tag, consumer) do
    send(owner, {:image_pull_request_started, self(), image_tag, consumer})
    finish(outcome, consumer)
  end

  defp finish(:success, consumer) do
    send(consumer, {:hackney_response, make_ref(), {:status, 200, "OK"}})
    send(consumer, {:hackney_response, make_ref(), :done})
    {:ok, :response}
  end

  defp finish({:error, reason}, _consumer), do: {:error, reason}
  defp finish({:exit, reason}, _consumer), do: exit(reason)

  defp finish(:wait, _consumer) do
    receive do
      :finish -> {:ok, :response}
    end
  end
end
