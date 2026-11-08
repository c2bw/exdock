defmodule Exdock.ReadModel.Projection do
  @moduledoc false

  @callback from_query(term()) :: map()
  @callback from_broadcast(term()) :: map()
end
