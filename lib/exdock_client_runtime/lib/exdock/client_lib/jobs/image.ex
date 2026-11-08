defmodule Exdock.ClientLib.Jobs.Image do
  @moduledoc """
  Executes image-scoped Docker jobs.
  """

  alias Exdock.ClientLib.Jobs.{ActionRunner, Context}
  alias Exdock.Docker.Error

  @spec image_delete(String.t(), String.t(), Context.t()) ::
          {:ok, String.t()} | {:error, Error.t(), String.t()}
  def image_delete(_job_id, id, %Context{} = context) do
    ActionRunner.run(
      "Deleting",
      "Deleted",
      "Delete",
      "image",
      id,
      fn engine, conn ->
        engine.delete_image(conn, id)
      end,
      context
    )
  end

  @spec image_pull(String.t(), String.t(), Context.t()) ::
          {:ok, String.t()} | {:error, Error.t(), String.t()}
  def image_pull(job_id, tag, %Context{} = context) do
    ActionRunner.run(
      "Pulling",
      "Pulled",
      "Pull",
      "image",
      tag,
      fn engine, conn ->
        engine.pull_image(conn, tag, true, :image_pull, job_id)
      end,
      context
    )
  end
end
