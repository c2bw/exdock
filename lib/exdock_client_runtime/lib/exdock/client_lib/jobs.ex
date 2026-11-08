defmodule Exdock.ClientLib.Jobs do
  @moduledoc """
  Stable job-handler facade callable by `Exdock.AgentRuntime.Executor`.

  Public function names are protocol job names. Domain modules own the Docker
  workflows while this facade keeps the command-dispatch contract unchanged.
  """

  alias Exdock.ClientLib.Jobs.{Container, Context, Image, Node}

  def node_refresh(job_id, opts, context \\ Context.runtime()),
    do: Node.node_refresh(job_id, opts, context)

  def container_recreate(job_id, id, pull_image, context \\ Context.runtime()),
    do: Container.container_recreate(job_id, id, pull_image, context)

  def container_start(job_id, id, context \\ Context.runtime()),
    do: Container.container_start(job_id, id, context)

  def container_stop(job_id, id, context \\ Context.runtime()),
    do: Container.container_stop(job_id, id, context)

  def container_restart(job_id, id, context \\ Context.runtime()),
    do: Container.container_restart(job_id, id, context)

  def container_resources(job_id, id, context \\ Context.runtime()),
    do: Container.container_resources(job_id, id, context)

  def image_delete(job_id, id, context \\ Context.runtime()),
    do: Image.image_delete(job_id, id, context)

  def image_pull(job_id, tag, context \\ Context.runtime()),
    do: Image.image_pull(job_id, tag, context)

  def container_logs(job_id, id),
    do: Container.container_logs(job_id, id, [], Context.runtime())

  def container_logs(job_id, id, opts) when is_list(opts),
    do: Container.container_logs(job_id, id, opts, Context.runtime())

  def container_logs(job_id, id, opts, %Context{} = context),
    do: Container.container_logs(job_id, id, opts, context)
end
