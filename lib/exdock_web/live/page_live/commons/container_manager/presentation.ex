defmodule ExdockWeb.Commons.ContainerManager.Presentation do
  @moduledoc "Presentation contract shared by container-manager status components."

  alias Exdock.Container.Policy
  alias Exdock.Datetime
  alias Exdock.ReadModel.Container

  @type status_message ::
          {:running, String.t() | nil, String.t()}
          | {:stopped, String.t() | nil}
          | {:restarting}
          | {:unknown, Date.t()}
          | {:updated, Date.t()}
          | {:outdated, Date.t(), Date.t(), integer()}
          | {:error, term()}
          | {:image_present, boolean()}

  @type info_message :: {:stack, String.t()} | :recreate_disabled

  @type t :: %__MODULE__{
          status_messages: [status_message()],
          info_messages: [info_message()],
          local_digest: String.t(),
          remote_digest: String.t(),
          show_remote_digest?: boolean()
        }

  defstruct status_messages: [],
            info_messages: [],
            local_digest: "Unavailable",
            remote_digest: "Unavailable",
            show_remote_digest?: false

  @spec build(String.t(), Container.core(), DateTime.t()) :: t()
  def build(container_name, core, clock_now) do
    %__MODULE__{
      status_messages: status_messages(core, clock_now),
      info_messages: info_messages(container_name, core),
      local_digest: display_digest(core.image_data.image.digest),
      remote_digest: display_digest(core.image_data.tag_info.latest_digest),
      show_remote_digest?: core.is_running and core.image_data.status != :updated
    }
  end

  defp info_messages(container_name, core) do
    []
    |> maybe_prepend(core.stack_name != "", {:stack, core.stack_name})
    |> maybe_prepend(not Policy.recreatable?(container_name, core), :recreate_disabled)
  end

  defp status_messages(core, clock_now) do
    run_state = run_state(core, clock_now)
    image_state = image_state(core)

    image_present =
      if core.image_data.status == :outdated,
        do: {:image_present, core.image_data.present_on_node},
        else: nil

    Enum.reject([run_state, image_state, image_present], &is_nil/1)
  end

  defp run_state(%{state: %{restarting: true}}, _clock_now), do: {:restarting}

  defp run_state(%{is_running: true} = core, clock_now) do
    cog_color =
      if Container.runtime_state(core, clock_now) == :just_started,
        do: "text-warning",
        else: "text-success"

    {:running, Datetime.elapsed_since(core.state.started_at, clock_now), cog_color}
  end

  defp run_state(core, clock_now),
    do: {:stopped, Datetime.elapsed_since(core.state.finished_at, clock_now)}

  defp image_state(%{image_data: image_data}) do
    local_build = DateTime.to_date(image_data.image.build_date)

    case image_data.status do
      :unknown ->
        {:unknown, local_build}

      :updated ->
        {:updated, local_build}

      :outdated ->
        remote_build = DateTime.to_date(image_data.tag_info.latest_date)

        {:outdated, local_build, remote_build,
         datetime_diff_in_days(image_data.image.build_date, image_data.tag_info.latest_date)}

      error ->
        {:error, error}
    end
  end

  defp display_digest(digest) when is_binary(digest) and digest != "", do: digest
  defp display_digest(_digest), do: "Unavailable"

  defp datetime_diff_in_days(date1, date2),
    do: trunc(DateTime.diff(date2, date1, :second) / (60 * 60 * 24))

  defp maybe_prepend(messages, true, message), do: [message | messages]
  defp maybe_prepend(messages, false, _message), do: messages
end
