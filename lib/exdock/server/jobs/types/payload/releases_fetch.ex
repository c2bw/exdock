defmodule Exdock.Server.Jobs.Payload.ReleasesFetch do
  @moduledoc "Repository labels and baseline releases attached to a release fetch job."

  alias Exdock.Domain.Repository.Release

  @enforce_keys [:repositories, :releases_list]
  defstruct [:repositories, :releases_list]

  @type repository :: {atom(), String.t()}
  @type t :: %__MODULE__{repositories: [repository()], releases_list: [Release.t()]}

  @spec new([repository()], [Release.t()]) :: t()
  def new(repositories, releases_list) when is_list(repositories) and is_list(releases_list),
    do: %__MODULE__{repositories: repositories, releases_list: releases_list}
end
