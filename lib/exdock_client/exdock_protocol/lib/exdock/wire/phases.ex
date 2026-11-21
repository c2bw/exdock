defmodule Exdock.Wire.Phases do
  def server,
    do: [
      initial: :initializing,
      ready: :ready,
      states: %{
        initializing: %{incoming: [:ready], outgoing: [:runtime_bundle], next: [:ready]},
        ready: %{incoming: [:progress, :result, :resource_sample], outgoing: [:command], next: []}
      }
    ]

  def client,
    do: [
      initial: :initializing,
      ready: :ready,
      states: %{
        initializing: %{incoming: [:runtime_bundle], outgoing: [:ready], next: [:ready]},
        ready: %{incoming: [:command], outgoing: [:progress, :result, :resource_sample], next: []}
      }
    ]
end
