defmodule Exdock.Docker.Local.Types do
  @moduledoc """
  Opaque transport types at the generated Docker client boundary.

  Application code uses these types instead of depending on a particular HTTP
  adapter's connection or response structs.
  """

  @type connection :: term()
  @type response :: term()
  @type error :: term()
  @type result(value) :: {:ok, value} | {:error, error()}
end
