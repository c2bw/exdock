defmodule Exdock.Server.State.Storage.Settings.Importer.Plan do
  @moduledoc false

  alias Exdock.Configuration
  alias Exdock.NodeId

  defstruct sections: [], warnings: []

  @type field ::
          :user_settings
          | :nodes_settings
          | :repository_overrides
          | :containers_settings
          | :images_settings
  @type entry :: map() | {String.t(), map()} | {String.t(), String.t(), map()}
  @type warning :: {:invalid_section, String.t()} | {:unknown_node, term()}
  @type t :: %__MODULE__{
          sections: [{field(), map() | [entry()]}],
          warnings: [warning()]
        }

  @labels %{
    user_settings: "user settings",
    nodes_settings: "nodes settings",
    repository_overrides: "repository overrides",
    containers_settings: "containers settings",
    images_settings: "images settings"
  }

  @spec build(map(), MapSet.t(String.t())) :: t()
  def build(import_data, known_nodes) when is_map(import_data) do
    Configuration.section_fields()
    |> Enum.reduce(%__MODULE__{}, fn field, plan ->
      plan_field(plan, field, Map.get(import_data, field), known_nodes)
    end)
    |> reverse_plan()
  end

  defp plan_field(plan, :user_settings, nil, _known_nodes), do: plan

  defp plan_field(plan, :user_settings, value, _known_nodes) when is_map(value),
    do: add_section(plan, :user_settings, value)

  defp plan_field(plan, field, value, known_nodes)
       when field in [:nodes_settings, :containers_settings, :images_settings] and is_map(value) do
    {node_entries, warnings} = known_node_entries(value, known_nodes)

    entries =
      case field do
        :nodes_settings -> node_entries
        _nested -> Enum.flat_map(node_entries, &nested_entries/1)
      end

    plan
    |> add_section(field, entries)
    |> add_warnings(warnings)
  end

  defp plan_field(plan, :repository_overrides, value, _known_nodes) when is_map(value),
    do: add_section(plan, :repository_overrides, setting_entries(value))

  defp plan_field(plan, field, _value, _known_nodes),
    do: add_warning(plan, {:invalid_section, Map.fetch!(@labels, field)})

  defp known_node_entries(settings_by_node, known_nodes) do
    settings_by_node
    |> setting_entries()
    |> Enum.reduce({[], []}, fn {node, settings}, {entries, warnings} ->
      if NodeId.valid?(node) and MapSet.member?(known_nodes, node) do
        {[{node, settings} | entries], warnings}
      else
        {entries, [{:unknown_node, node} | warnings]}
      end
    end)
  end

  defp nested_entries({node, settings_by_name_or_id}) do
    Enum.map(setting_entries(settings_by_name_or_id), fn {name_or_id, settings} ->
      {node, name_or_id, settings}
    end)
  end

  defp setting_entries(source) when is_map(source), do: Enum.filter(source, &valid_setting_entry?/1)
  defp setting_entries(_source), do: []

  defp valid_setting_entry?({key, settings}),
    do: is_binary(key) and key != "" and is_map(settings)

  defp valid_setting_entry?(_entry), do: false

  defp add_section(%__MODULE__{sections: sections} = plan, field, entries),
    do: %{plan | sections: [{field, entries} | sections]}

  defp add_warning(%__MODULE__{warnings: warnings} = plan, warning),
    do: %{plan | warnings: [warning | warnings]}

  defp add_warnings(%__MODULE__{} = plan, warnings),
    do: %{plan | warnings: warnings ++ plan.warnings}

  defp reverse_plan(%__MODULE__{} = plan),
    do: %{plan | sections: Enum.reverse(plan.sections), warnings: Enum.reverse(plan.warnings)}
end
