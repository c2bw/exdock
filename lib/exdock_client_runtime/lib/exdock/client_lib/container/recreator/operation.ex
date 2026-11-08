defmodule Exdock.ClientLib.Container.Recreator.Operation do
  @moduledoc """
  Declarative Docker operation interpreter for container recreation.

  Workflow and rollback code describe intent as data; this module is the only
  recreation layer that invokes the injected Docker adapter.
  """

  @type t ::
          {:inspect, String.t()}
          | {:inspect_image, String.t()}
          | {:stop, String.t()}
          | {:rename, String.t(), String.t()}
          | {:disconnect, String.t(), String.t(), struct()}
          | {:connect, String.t(), String.t(), struct()}
          | {:create, String.t(), struct()}
          | {:start, String.t()}
          | {:delete, String.t()}

  @spec execute(module(), term(), t()) :: {:ok, term()} | {:error, term()}
  def execute(ops, conn, operation) do
    invoke(ops, conn, operation)
  rescue
    exception -> {:error, exception}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp invoke(ops, conn, {:inspect, id}), do: ops.inspect(conn, id)
  defp invoke(ops, conn, {:inspect_image, reference}), do: ops.inspect_image(conn, reference)
  defp invoke(ops, conn, {:stop, id}), do: ops.stop(conn, id)
  defp invoke(ops, conn, {:rename, id, name}), do: ops.rename(conn, id, name)
  defp invoke(ops, conn, {:disconnect, _id, network, request}), do: ops.disconnect(conn, network, request)
  defp invoke(ops, conn, {:connect, _id, network, request}), do: ops.connect(conn, network, request)
  defp invoke(ops, conn, {:create, name, request}), do: ops.create(conn, name, request)
  defp invoke(ops, conn, {:start, id}), do: ops.start(conn, id)
  defp invoke(ops, conn, {:delete, id}), do: ops.delete(conn, id)
end
