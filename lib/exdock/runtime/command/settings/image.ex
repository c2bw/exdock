defmodule Exdock.Runtime.Command.Settings.Image do
  @moduledoc false

  @behaviour Exdock.Runtime.Command.Handler

  alias Exdock.Runtime.Command.MutationExecutor
  alias Exdock.Runtime.Command.Validation
  alias Exdock.Runtime.Mutation

  @actions [
    :set_image_delete_lock,
    :set_image_repository_url,
    :set_image_repository_urls
  ]

  defstruct [:action, :data, :mutation]

  @type t :: %__MODULE__{
          action:
            :set_image_delete_lock
            | :set_image_repository_url
            | :set_image_repository_urls,
          data: term(),
          mutation: Exdock.Runtime.Mutation.t() | nil
        }

  @spec image_delete_lock(term(), String.t(), boolean()) :: t()
  def image_delete_lock(node, image_id, locked),
    do: command(:set_image_delete_lock, {node, image_id, locked})

  @spec image_repository_url(String.t(), String.t()) :: t()
  def image_repository_url(image_name, repository_url),
    do: command(:set_image_repository_url, {image_name, repository_url})

  @spec image_repository_urls([{String.t(), String.t()}]) :: t()
  def image_repository_urls(overrides),
    do: command(:set_image_repository_urls, overrides)

  @impl true
  def kind(%__MODULE__{action: action}) when action in @actions, do: action

  @impl true
  def normalize(
        %__MODULE__{
          action: :set_image_delete_lock,
          data: {node, image_id, locked}
        } = command
      ) do
    with {:ok, node} <- Validation.runtime_node(node) do
      MutationExecutor.attach(command, Mutation.image_delete_lock(node, image_id, locked))
    end
  end

  def normalize(
        %__MODULE__{
          action: :set_image_repository_url,
          data: {image_name, repository_url}
        } = command
      ) do
    MutationExecutor.attach(command, Mutation.image_repository_url(image_name, repository_url))
  end

  def normalize(
        %__MODULE__{
          action: :set_image_repository_urls,
          data: overrides
        } = command
      ),
      do: MutationExecutor.attach(command, Mutation.image_repository_urls(overrides))

  def normalize(%__MODULE__{}), do: {:error, :invalid_command}

  @impl true
  defdelegate execute(state, command), to: MutationExecutor

  defp command(action, data), do: %__MODULE__{action: action, data: data}
end
