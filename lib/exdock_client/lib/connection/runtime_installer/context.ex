defmodule Exdock.Client.Connection.RuntimeInstaller.Context do
  @moduledoc """
  Typed dependencies and rollback state for one runtime upgrade transaction.
  """

  @default_stop_timeout 5_000

  @type module_snapshot :: %{
          module() => {:loaded, binary(), String.t() | charlist()} | :unloaded
        }

  @enforce_keys [:ops, :runtime_supervisor]
  defstruct [:installed_modules, :ops, :runtime_supervisor, stop_timeout: @default_stop_timeout]

  @type t :: %__MODULE__{
          installed_modules: module_snapshot() | nil,
          ops: module(),
          runtime_supervisor: atom(),
          stop_timeout: pos_integer()
        }
end
