defmodule Exdock.Runtime.Command.Image do
  @moduledoc false

  @behaviour Exdock.Runtime.Command.Handler

  alias Exdock.Runtime.Command.Validation
  alias Exdock.Server.Jobs
  alias Exdock.Server.State

  @actions [:pull_images, :delete_image, :delete_unused_images]

  defstruct [:action, :node, :image_id, :images]

  @type image_pull :: %{
          required(:node) => String.t(),
          required(:image_tag) => String.t()
        }

  @type t :: %__MODULE__{
          action: :pull_images | :delete_image | :delete_unused_images,
          node: String.t() | nil,
          image_id: String.t() | nil,
          images: [image_pull()] | nil
        }

  @spec pull([image_pull()]) :: t()
  def pull(images), do: %__MODULE__{action: :pull_images, images: images}

  @spec delete(term(), String.t()) :: t()
  def delete(node, image_id),
    do: %__MODULE__{
      action: :delete_image,
      node: node,
      image_id: image_id
    }

  @spec delete_unused(term()) :: t()
  def delete_unused(node),
    do: %__MODULE__{action: :delete_unused_images, node: node}

  @impl true
  def kind(%__MODULE__{action: action}) when action in @actions, do: action

  @impl true
  def normalize(%__MODULE__{action: :pull_images, images: images} = command)
      when is_list(images) do
    with {:ok, images} <- normalize_image_pulls(images) do
      {:ok, %{command | images: images}}
    end
  end

  def normalize(%__MODULE__{action: :delete_image, image_id: image_id} = command)
      when is_binary(image_id) do
    with {:ok, node} <- Validation.runtime_node(command.node) do
      {:ok, %{command | node: node}}
    end
  end

  def normalize(%__MODULE__{action: :delete_unused_images} = command) do
    with {:ok, node} <- Validation.runtime_node(command.node) do
      {:ok, %{command | node: node}}
    end
  end

  def normalize(%__MODULE__{}), do: {:error, :invalid_command}

  @impl true
  def execute(
        %State{} = state,
        %__MODULE__{action: :pull_images, images: images}
      ),
      do: work(Jobs.Client.Image.pull(state, images))

  def execute(
        %State{} = state,
        %__MODULE__{
          action: :delete_image,
          node: node,
          image_id: image_id
        }
      ),
      do: work(Jobs.Client.Image.delete(state, node, image_id))

  def execute(
        %State{} = state,
        %__MODULE__{action: :delete_unused_images, node: node}
      ),
      do: work(Jobs.Client.Image.delete_unused(state, node))

  defp normalize_image_pulls(images) do
    Validation.map_all(images, fn
      %{node: node, image_tag: tag} when is_binary(tag) ->
        with {:ok, node} <- Validation.runtime_node(node) do
          {:ok, %{node: node, image_tag: tag}}
        end

      _invalid ->
        {:error, :invalid_image_pull}
    end)
  end

  defp work(work), do: {:work, work}
end
