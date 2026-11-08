defmodule Exdock.Build.ProjectConfig do
  @moduledoc false

  @release_tracks %{
    control_plane: %{version: "0.1.1", elixir: "~> 1.20"},
    runtime_protocol: %{version: "0.1.0", elixir: "~> 1.18"}
  }

  @spec project(atom(), atom(), keyword()) :: keyword()
  def project(app, release_track, options) when is_atom(app) and is_list(options) do
    %{version: version, elixir: elixir} = Map.fetch!(@release_tracks, release_track)

    [app: app, version: version, elixir: elixir]
    |> Keyword.merge(options)
  end
end
