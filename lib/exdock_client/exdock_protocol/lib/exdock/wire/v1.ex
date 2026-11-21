defmodule Exdock.Wire.V1 do
  @moduledoc "Native NodeWire protocol; incompatible with retired Exdock wire-v4."
  use NodeWire.Protocol, id: "exdock.agent", version: 1, codec: :erlang_term, capabilities: ["jobs.v1", "metrics.v1"]
  message(:runtime_bundle, id: 1)
  message(:ready, id: 2)
  message(:command, id: 3)
  message(:progress, id: 4)
  message(:result, id: 5)
  message(:resource_sample, id: 6)
end
