defmodule Exdock.Configuration do
  @moduledoc """
  Public import, export, and lookup boundary for the effective configuration.

  Runtime storage is split across node, image, and container modules while
  delivery layers exchange one stable configuration structure.
  """

  @user_settings_key "user_settings"
  @nodes_settings_key "nodes_settings"
  @images_settings_key "images_settings"
  @containers_settings_key "containers_settings"
  @repository_overrides_key "repository_overrides"

  @export_sections [
    {:user_settings, @user_settings_key, nil},
    {:nodes_settings, @nodes_settings_key, %{}},
    {:images_settings, @images_settings_key, %{}},
    {:containers_settings, @containers_settings_key, %{}},
    {:repository_overrides, @repository_overrides_key, %{}}
  ]

  @derive Jason.Encoder
  defstruct user_settings: nil,
            nodes_settings: %{},
            images_settings: %{},
            containers_settings: %{},
            repository_overrides: %{}

  @type settings :: %{optional(atom() | String.t()) => term()}
  @type grouped_settings :: %{optional(String.t()) => settings()}

  @type t :: %__MODULE__{
          user_settings: settings() | nil,
          nodes_settings: grouped_settings(),
          images_settings: %{optional(String.t()) => grouped_settings()},
          containers_settings: %{optional(String.t()) => grouped_settings()},
          repository_overrides: grouped_settings()
        }

  @spec from_json(binary()) :: {:ok, t()} | {:error, binary()}
  def from_json(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, data} when is_map(data) -> {:ok, from_export_map(data)}
      {:ok, _data} -> {:error, "expected an object"}
      {:error, error} -> {:error, Jason.DecodeError.message(error)}
    end
  end

  @spec to_json(t()) :: binary()
  def to_json(%__MODULE__{} = configuration) do
    configuration
    |> to_export_map()
    |> Jason.encode!()
    |> Jason.Formatter.pretty_print()
  end

  @doc false
  @spec section_fields() :: [atom()]
  def section_fields, do: Enum.map(@export_sections, &elem(&1, 0))

  @doc false
  @spec import_sections(t()) :: %{
          user_settings: map() | nil,
          nodes_settings: map(),
          images_settings: map(),
          containers_settings: map(),
          repository_overrides: map()
        }
  def import_sections(%__MODULE__{} = configuration) do
    Map.new(@export_sections, fn {field, _json_key, _default} ->
      {field, configuration |> Map.fetch!(field) |> serialize_value()}
    end)
  end

  @spec node_settings(t(), String.t()) :: settings()
  def node_settings(%__MODULE__{nodes_settings: nodes_settings}, node) when is_binary(node),
    do: Map.get(nodes_settings, node, %{web_ui: ""})

  defp to_export_map(%__MODULE__{} = configuration) do
    sections = import_sections(configuration)
    Map.new(@export_sections, &export_section(sections, &1))
  end

  defp export_section(sections, {field, json_key, _default}) when is_map(sections) do
    {json_key, Map.fetch!(sections, field)}
  end

  defp serialize_value(nil), do: nil
  defp serialize_value(%_{} = value), do: value |> Map.from_struct() |> serialize_map()
  defp serialize_value(%{} = value), do: serialize_map(value)
  defp serialize_value(values) when is_list(values), do: Enum.map(values, &serialize_value/1)
  defp serialize_value(value), do: value

  defp serialize_map(values) when is_map(values) do
    Map.new(values, fn {key, value} -> {serialize_key(key), serialize_value(value)} end)
  end

  defp serialize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp serialize_key(key), do: key

  defp from_export_map(%{} = data) do
    struct!(__MODULE__, Map.new(@export_sections, &import_section(data, &1)))
  end

  defp import_section(%{} = data, {field, json_key, default}) do
    {field, Map.get(data, json_key, default)}
  end
end
