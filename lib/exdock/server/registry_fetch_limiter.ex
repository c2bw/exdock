defmodule Exdock.Server.RegistryFetchLimiter do
  @moduledoc """
  Limits registry image checks by canonical registry endpoint.

  The GenServer owns caller monitors and interprets lease effects. FIFO lease
  state transitions live in `LeaseState`.
  """

  use GenServer

  alias Exdock.Server.RegistryFetchLimiter.LeaseState
  alias Exdock.Server.RegistryFetchLimiter.LeaseState.Waiter
  alias Regc.Oci.{Error, Reference}

  @docker_hub_registries [
    "docker.io",
    "index.docker.io",
    "registry-1.docker.io"
  ]
  @max_concurrency 1

  @type endpoint :: LeaseState.endpoint()

  @doc """
  Starts the shared limiter.

  Passing `name: nil` starts an unregistered limiter for isolated tests.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, :ok)
      name -> GenServer.start_link(__MODULE__, :ok, name: name)
    end
  end

  @doc """
  Runs `function` while holding the lease for `image_reference`.

  The lease is released even when the function raises, throws, or exits.
  """
  @spec run(String.t(), (-> result), GenServer.server()) :: result
        when result: term()
  def run(image_reference, function, server \\ __MODULE__)
      when is_binary(image_reference) and is_function(function, 0) do
    case endpoint(image_reference) do
      {:ok, endpoint} ->
        lease = GenServer.call(server, {:acquire, endpoint}, :infinity)

        try do
          function.()
        after
          GenServer.cast(server, {:release, endpoint, lease})
        end

      {:error, %Error{} = error} ->
        raise error
    end
  end

  @doc false
  @spec max_concurrency() :: pos_integer()
  def max_concurrency, do: @max_concurrency

  @doc """
  Returns the canonical registry endpoint for an image reference.
  """
  @spec endpoint(String.t()) :: {:ok, endpoint()} | {:error, Error.t()}
  def endpoint(image_reference) when is_binary(image_reference) do
    case Reference.parse(image_reference) do
      {:ok, %Reference{scheme: scheme, registry: registry}} ->
        {:ok, {scheme, canonical_registry(registry)}}

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  @impl true
  @spec init(:ok) :: {:ok, LeaseState.t()}
  def init(:ok), do: {:ok, LeaseState.new()}

  @impl true
  def handle_call({:acquire, endpoint}, from, state) do
    waiter = Waiter.new(from, Process.monitor(elem(from, 0)))

    case LeaseState.acquire(state, endpoint, waiter, @max_concurrency) do
      {:granted, lease, state} -> {:reply, lease, state}
      {:queued, state} -> {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:release, endpoint, lease}, state) do
    state
    |> LeaseState.release(endpoint, lease, @max_concurrency)
    |> interpret_transition()
  end

  @impl true
  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    state
    |> LeaseState.monitor_down(monitor, @max_concurrency)
    |> interpret_transition()
  end

  defp interpret_transition({state, effects}) do
    Enum.each(effects, &run_effect/1)
    {:noreply, state}
  end

  defp run_effect({:demonitor, monitor}),
    do: Process.demonitor(monitor, [:flush])

  defp run_effect({:reply, from, lease}),
    do: GenServer.reply(from, lease)

  defp canonical_registry(registry)
       when registry in @docker_hub_registries,
       do: "registry-1.docker.io"

  defp canonical_registry(registry), do: registry
end
