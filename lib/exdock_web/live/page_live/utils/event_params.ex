defmodule ExdockWeb.PageLive.Utils.EventParams do
  @moduledoc false

  alias Exdock.Container.Policy

  @spec priority(any()) :: {:ok, integer()} | {:error, :invalid_priority}
  def priority(value) when is_binary(value) do
    case Integer.parse(value) do
      {priority, ""} -> validate_priority(priority)
      _ -> {:error, :invalid_priority}
    end
  end

  def priority(value) when is_integer(value), do: validate_priority(value)
  def priority(_value), do: {:error, :invalid_priority}

  @spec boolean(any()) :: {:ok, boolean()} | {:error, :invalid_boolean}
  def boolean("true"), do: {:ok, true}
  def boolean("false"), do: {:ok, false}
  def boolean(true), do: {:ok, true}
  def boolean(false), do: {:ok, false}
  def boolean(_value), do: {:error, :invalid_boolean}

  @spec image_delete(any()) :: {:ok, {String.t(), String.t()}} | {:error, :invalid_image_delete}
  def image_delete(%{"nodename" => node, "imageid" => image_id}) do
    with {:ok, node} <- non_empty_string(node),
         {:ok, image_id} <- non_empty_string(image_id) do
      {:ok, {node, image_id}}
    else
      :error -> {:error, :invalid_image_delete}
    end
  end

  def image_delete(_params), do: {:error, :invalid_image_delete}

  @spec image_cleanup(any()) :: {:ok, String.t()} | {:error, :invalid_image_cleanup}
  def image_cleanup(%{"node" => node}) do
    case non_empty_string(node) do
      {:ok, node} -> {:ok, node}
      :error -> {:error, :invalid_image_cleanup}
    end
  end

  def image_cleanup(_params), do: {:error, :invalid_image_cleanup}

  @spec image_lock(any()) ::
          {:ok, {String.t(), String.t(), boolean()}} | {:error, :invalid_image_lock}
  def image_lock(%{"nodename" => node, "imageid" => image_id, "tolock" => to_lock}) do
    with {:ok, node} <- non_empty_string(node),
         {:ok, image_id} <- non_empty_string(image_id),
         {:ok, lock?} <- boolean(to_lock) do
      {:ok, {node, image_id, lock?}}
    else
      _invalid -> {:error, :invalid_image_lock}
    end
  end

  def image_lock(_params), do: {:error, :invalid_image_lock}

  @spec repository(any()) :: {:ok, String.t()} | {:error, :invalid_repository}
  def repository(%{"repository" => repository}) do
    case non_empty_string(repository) do
      {:ok, repository} -> {:ok, repository}
      :error -> {:error, :invalid_repository}
    end
  end

  def repository(_params), do: {:error, :invalid_repository}

  @spec image_jobs(any()) ::
          {:ok, [%{node: String.t(), image_tag: String.t()}]}
          | {:error, :invalid_image_jobs}
  def image_jobs(%{"images" => images}) when is_list(images),
    do: parse_entries(images, &parse_image_job/1, :invalid_image_jobs)

  def image_jobs(%{"node" => node, "image_tag" => image_tag}),
    do: parse_entries([%{"node" => node, "image_tag" => image_tag}], &parse_image_job/1, :invalid_image_jobs)

  def image_jobs(_params), do: {:error, :invalid_image_jobs}

  @spec container_jobs(any()) ::
          {:ok, [{String.t(), String.t()}]}
          | {:error, :invalid_container_jobs}
  def container_jobs(%{"containers" => containers}) when is_list(containers),
    do: parse_entries(containers, &parse_container_job/1, :invalid_container_jobs)

  def container_jobs(%{"node" => node, "container_name" => name}),
    do: parse_entries([%{"node" => node, "name" => name}], &parse_container_job/1, :invalid_container_jobs)

  def container_jobs(_params), do: {:error, :invalid_container_jobs}

  defp parse_entries([], _parser, error), do: {:error, error}

  defp parse_entries(entries, parser, error) do
    Exdock.Result.traverse(entries, fn entry ->
      case parser.(entry) do
        {:ok, value} -> {:ok, value}
        :error -> {:error, error}
      end
    end)
  end

  defp parse_image_job(%{"node" => node, "image_tag" => image_tag}) do
    with {:ok, node} <- non_empty_string(node),
         {:ok, image_tag} <- non_empty_string(image_tag) do
      {:ok, %{node: node, image_tag: image_tag}}
    else
      :error -> :error
    end
  end

  defp parse_image_job(_job), do: :error

  defp parse_container_job(%{"node" => node, "name" => name}) do
    with {:ok, node} <- non_empty_string(node),
         {:ok, name} <- non_empty_string(name) do
      {:ok, {node, name}}
    else
      :error -> :error
    end
  end

  defp parse_container_job(_job), do: :error

  defp non_empty_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> :error
      value -> {:ok, value}
    end
  end

  defp non_empty_string(_value), do: :error

  defp validate_priority(priority) do
    if Policy.valid_priority?(priority) do
      {:ok, priority}
    else
      {:error, :invalid_priority}
    end
  end
end
