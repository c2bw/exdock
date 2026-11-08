defmodule Exdock.Server.Jobs.Client.Image do
  @moduledoc """
  Builds remote image jobs from server-side cluster data.

  Image operations are sent to connected nodes through the job dispatcher. This
  module filters invalid/no-op requests before they reach the remote client.
  """

  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.Detail
  alias Exdock.Server.Jobs.Payload.ImageAction
  alias Exdock.Server.Jobs.Spec
  alias Exdock.Server.State
  alias Exdock.Server.State.Storage
  alias Exdock.Domain

  @doc """
  Delete a single image from a node when it exists in the current snapshot.
  """
  @spec delete(State.t(), String.t(), String.t()) :: Jobs.Detail.t() | nil
  def delete(%State{cluster: %Storage.Cluster{storage: storage}}, node, id)
      when is_binary(node) and is_binary(id) do
    storage
    |> Storage.Images.by_id(node, id)
    |> image_delete_work()
  end

  @doc """
  Delete all unused, unlocked images from a node.
  """
  @spec delete_unused(State.t(), String.t()) :: [Jobs.Detail.t()]
  def delete_unused(%State{cluster: %Storage.Cluster{storage: storage}}, node)
      when is_binary(node) do
    # Bulk cleanup is always one payload so all removals are treated as one operation.
    unused_image_delete_details(storage, node)
  end

  defp image_delete_work(nil), do: nil
  defp image_delete_work(%Domain.Image{} = image), do: image_delete_detail(image)

  defp unused_image_delete_details(storage, node) when is_binary(node) do
    storage
    |> Storage.Images.list_node(node)
    |> Enum.filter(&image_reclaimable?/1)
    |> Enum.map(&image_delete_detail/1)
  end

  # Explicit single-image delete bypasses reclaimability checks; bulk cleanup
  # only removes unused, unlocked images.
  defp image_reclaimable?(%Domain.Image{} = image),
    do: not Domain.Image.in_use?(image) and not Domain.Image.locked?(image)

  @spec image_delete_detail(Domain.Image.t()) :: Jobs.Detail.t()
  defp image_delete_detail(%Domain.Image{node: node, id: id, tags: tags}) do
    build_image_detail(:image_delete, node, [id], image_delete_data(node, id, tags))
  end

  @doc """
  Pull one or more image tags on their target nodes.

  Multiple pulls are packaged so progress and final status can be displayed as
  one operation while each pull still reports independently.
  """
  @spec pull(State.t(), list(%{node: String.t(), image_tag: String.t()})) :: Jobs.Detail.t() | Jobs.Package.t() | nil
  def pull(%State{}, jobs) when is_list(jobs), do: pull_work(jobs)

  @spec pull_work(list(%{node: String.t(), image_tag: String.t()})) :: Jobs.Detail.t() | Jobs.Package.t() | nil
  defp pull_work([]), do: nil

  # Single pulls stay as plain details; multiple pulls are packaged so the batch
  # logs as one operation.
  defp pull_work([job]), do: build_pull_request(job)

  defp pull_work(jobs) when is_list(jobs) do
    details = Enum.map(jobs, &build_pull_request/1)
    Jobs.Package.new(:image_pull, details, pull_package_metadata(details, jobs))
  end

  @spec build_pull_request(%{node: String.t(), image_tag: String.t()}) :: Jobs.Detail.t()
  defp build_pull_request(%{node: node, image_tag: image_tag}) do
    image_pull_detail(node, image_tag)
  end

  @doc false
  @spec do_pull(String.t(), String.t()) :: Jobs.Detail.t()
  def do_pull(node, image_tag) when is_binary(node) and is_binary(image_tag) do
    image_pull_detail(node, image_tag)
  end

  defp image_pull_detail(node, image_tag) when is_binary(node) and is_binary(image_tag) do
    build_image_detail(:image_pull, node, [image_tag], image_pull_data(node, image_tag))
  end

  defp build_image_detail(name, node, parameters, data)
       when is_atom(name) and is_binary(node) and is_list(parameters) and is_map(data) do
    Detail.new(name, Spec.new(Spec.Remote.new(node), parameters, data))
  end

  defp image_delete_data(node, image_id, tags) when is_binary(node) and is_binary(image_id) do
    ImageAction.delete(node, image_id, tags)
  end

  defp image_pull_data(node, image_tag) when is_binary(node) and is_binary(image_tag) do
    ImageAction.pull(node, image_tag)
  end

  defp pull_package_metadata(details, jobs) when is_list(details) and is_list(jobs) do
    {length(details), Enum.map(jobs, & &1.image_tag)}
  end
end
