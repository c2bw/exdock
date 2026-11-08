defmodule ExdockWeb.PageLive.LivePage.ShellContext do
  @moduledoc """
  Builds the common rendering contract for operational page layouts.

  The context is rebuilt from current assigns on every render so values changed
  by broadcasts remain current without duplicating shell wiring in each page.
  """

  defstruct page: nil,
            flash: %{},
            current_user: nil,
            configuration_form: nil,
            modals_to_render: %{},
            active_modal_id: nil,
            server_configuration: nil,
            status: nil,
            nodes_list: [],
            client_latency: nil,
            js_render_time: nil,
            server_render_time: nil

  @type metric :: number() | nil
  @type t :: %__MODULE__{
          page: String.t(),
          flash: map(),
          current_user: struct() | map() | nil,
          configuration_form: struct() | nil,
          modals_to_render: map(),
          active_modal_id: String.t() | nil,
          server_configuration: struct() | nil,
          status: struct() | atom() | nil,
          nodes_list: [String.t()],
          client_latency: metric(),
          js_render_time: metric(),
          server_render_time: metric()
        }

  @spec build(map()) :: t()
  def build(assigns) when is_map(assigns) do
    %__MODULE__{
      page: Map.fetch!(assigns, :page),
      flash: Map.fetch!(assigns, :flash),
      current_user: Map.get(assigns, :current_user),
      configuration_form: Map.get(assigns, :settings_import_form),
      modals_to_render: Map.get(assigns, :modals_to_render, %{}),
      active_modal_id: Map.get(assigns, :active_modal_id),
      server_configuration: Map.get(assigns, :server_configuration),
      status: Map.get(assigns, :status),
      nodes_list: Map.get(assigns, :nodes_list, []),
      client_latency: Map.get(assigns, :client_latency),
      js_render_time: Map.get(assigns, :js_render_time),
      server_render_time: Map.get(assigns, :server_render_time)
    }
  end
end
