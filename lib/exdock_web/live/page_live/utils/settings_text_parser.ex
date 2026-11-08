defmodule ExdockWeb.PageLive.Utils.SettingsTextParser do
  @moduledoc """
  Parses the line-oriented settings formats accepted by bulk import forms.
  """

  alias Exdock.Container.Policy

  @spec repository_overrides(binary() | list()) ::
          {:ok, [{String.t(), String.t()}]}
          | {:error, :invalid_repository_overrides}
  def repository_overrides(value) when is_binary(value) do
    value
    |> non_empty_lines()
    |> parse_entries(&parse_override_line/1, :invalid_repository_overrides)
  end

  def repository_overrides(value) when is_list(value) do
    parse_entries(value, &parse_override/1, :invalid_repository_overrides)
  end

  def repository_overrides(_value), do: {:error, :invalid_repository_overrides}

  @spec container_priorities(binary() | list()) ::
          {:ok, [{String.t(), String.t(), integer()}]}
          | {:error, :invalid_container_priorities}
  def container_priorities(value) when is_binary(value) do
    value
    |> non_empty_lines()
    |> parse_entries(&parse_priority_line/1, :invalid_container_priorities)
  end

  def container_priorities(value) when is_list(value) do
    parse_entries(value, &parse_priority_entry/1, :invalid_container_priorities)
  end

  def container_priorities(_value), do: {:error, :invalid_container_priorities}

  defp non_empty_lines(value) do
    value
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_entries([], _parser, error), do: {:error, error}

  defp parse_entries(entries, parser, error) do
    Exdock.Result.traverse(entries, fn entry ->
      case parser.(entry) do
        {:ok, value} -> {:ok, value}
        :error -> {:error, error}
      end
    end)
  end

  defp parse_override_line(line) do
    case String.split(line, "->", parts: 2) do
      [image, repository_url] -> parse_override({image, repository_url})
      _invalid -> :error
    end
  end

  defp parse_override({image, repository_url})
       when is_binary(image) and is_binary(repository_url) do
    image = String.trim(image)
    repository_url = String.trim(repository_url)

    if image == "" or repository_url == "",
      do: :error,
      else: {:ok, {image, repository_url}}
  end

  defp parse_override(_entry), do: :error

  defp parse_priority_line(line) do
    case String.split(line, "->", parts: 3) do
      [node, name, priority] -> parse_priority_entry({node, name, priority})
      _invalid -> :error
    end
  end

  defp parse_priority_entry({node, name, priority})
       when is_binary(node) and is_binary(name) do
    node = String.trim(node)
    name = String.trim(name)
    priority = if(is_binary(priority), do: String.trim(priority), else: priority)

    with {priority, ""} <- Integer.parse(to_string(priority)),
         true <- Policy.valid_priority?(priority),
         true <- node != "" and name != "" do
      {:ok, {node, name, priority}}
    else
      _invalid -> :error
    end
  end

  defp parse_priority_entry(_entry), do: :error
end
