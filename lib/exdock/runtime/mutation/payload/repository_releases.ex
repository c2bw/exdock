defmodule Exdock.Runtime.Mutation.Payload.RepositoryReleases do
  @moduledoc "Typed repository release-fetch mutation payload."

  alias Exdock.Domain.Repository.Release

  @type result ::
          {:ok, String.t(), [Release.t()]}
          | {:error, String.t(), term()}

  @enforce_keys [:results]
  defstruct [:results]

  @type t :: %__MODULE__{results: [result()]}
end
