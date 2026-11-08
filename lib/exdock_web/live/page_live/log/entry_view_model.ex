defmodule ExdockWeb.PageLive.Log.EntryViewModel do
  @moduledoc """
  Normalizes server log payloads for the compact and detailed log renderers.

  Raw log tuples are decoded in one place so both renderers agree on action
  labels, pluralization, node references, and refresh statistics.
  """

  @node_actions %{
    container_recreate: {"recreate", "container"},
    container_start: {"start", "container"},
    container_stop: {"stop", "container"},
    container_restart: {"restart", "container"},
    container_logs: {"fetch container logs", "container"},
    image_delete: {"delete", "image"},
    image_pull: {"pull", "image"}
  }

  @type container_status_entry :: %{
          kind: :container_status,
          node: term(),
          name: term(),
          old_status: term(),
          new_status: term()
        }

  @type text_entry :: %{kind: :text, text: String.t()}

  @type releases_fetch_entry :: %{
          kind: :releases_fetch,
          text: String.t(),
          new_releases_count: non_neg_integer()
        }

  @type refresh_counts :: %{
          new: non_neg_integer(),
          vanished: non_neg_integer(),
          started: non_neg_integer(),
          stopped: non_neg_integer(),
          errored: non_neg_integer()
        }

  @type refresh_change_status ::
          {:new, term()}
          | {:ok, :vanished | boolean()}
          | {:error, term()}

  @type refresh_change :: {String.t(), term(), refresh_change_status()}

  @type node_refresh_entry :: %{
          kind: :node_refresh,
          text: String.t(),
          nodes: [String.t()],
          changes: [refresh_change()],
          counts: refresh_counts(),
          detailed?: boolean()
        }

  @type list_entry :: %{
          kind: :list,
          text: String.t(),
          detailed_text: String.t(),
          list: [term()]
        }

  @type node_action_entry :: %{
          kind: :node_action,
          node: term(),
          text: String.t(),
          detailed_text: String.t(),
          subject: String.t()
        }

  @type node_state_entry :: %{
          kind: :node_state,
          node: term(),
          text: String.t(),
          text_color: String.t()
        }

  @type limited_entries :: %{kind: :limited_entries}
  @type unknown_entry :: %{kind: :unknown, message_id: atom(), message_data: term()}

  @type t ::
          container_status_entry()
          | text_entry()
          | releases_fetch_entry()
          | node_refresh_entry()
          | list_entry()
          | node_action_entry()
          | node_state_entry()
          | limited_entries()
          | unknown_entry()

  @type status :: %{icon: String.t(), text_color: String.t()}

  @spec build(atom(), term()) :: t()
  def build(:container_status, {node, name, old_status, new_status}) do
    %{
      kind: :container_status,
      node: node,
      name: name,
      old_status: old_status,
      new_status: new_status
    }
  end

  def build(:registry_fetch, images_count) when is_integer(images_count) do
    %{kind: :text, text: "fetch [#{images_count}] #{pluralize(images_count, "image")}"}
  end

  def build(
        :releases_fetch,
        %{repos_count: repos_count, new_releases_count: new_releases_count}
      )
      when is_integer(repos_count) and is_integer(new_releases_count) do
    %{
      kind: :releases_fetch,
      text: "fetch [#{repos_count}] #{pluralize(repos_count, "repository", "repositories")}",
      new_releases_count: new_releases_count
    }
  end

  def build(:node_refresh, %{nodes: nodes, containers: containers}) do
    flattened = flatten_container_changes(containers)

    %{
      kind: :node_refresh,
      text: "refresh [#{Enum.count(nodes)}] #{pluralize(Enum.count(nodes), "node")}",
      nodes: Enum.map(nodes, &to_string/1),
      changes: refresh_changes(flattened),
      counts: refresh_counts(flattened),
      detailed?: flattened != [] and Enum.all?(flattened, fn {_node, _container, status} -> not match?({:before, _}, status) end)
    }
  end

  def build(:container_recreate, {:mass, {amount, containers, pull_image}})
      when is_integer(amount) and is_list(containers) and is_boolean(pull_image) do
    %{
      kind: :list,
      text: "mass recreate [#{amount}] containers",
      detailed_text: "mass #{if(pull_image, do: "pull and ")}recreate [#{amount}] containers",
      list: containers
    }
  end

  def build(:image_pull, {:mass, {amount, image_tags}})
      when is_integer(amount) and is_list(image_tags) do
    %{
      kind: :list,
      text: "mass pull [#{amount}] images",
      detailed_text: "mass pull [#{amount}] images",
      list: image_tags
    }
  end

  def build(message_id, {node, value}) when is_map_key(@node_actions, message_id) do
    {action, subject} = Map.fetch!(@node_actions, message_id)

    %{
      kind: :node_action,
      node: node,
      text: "#{action} [#{value}]",
      detailed_text: "#{action} [#{value}] node [#{node}]",
      subject: subject
    }
  end

  def build(:node_connected, node) do
    %{kind: :node_state, node: node, text: "node up", text_color: "text-lime-600"}
  end

  def build(:node_disconnected, node) do
    %{kind: :node_state, node: node, text: "node down", text_color: "text-warning"}
  end

  def build(:repository_overrides, {count}) when is_integer(count) do
    %{kind: :text, text: "set #{count} #{pluralize(count, "repository URL")}"}
  end

  def build(:containers_priorities, {count}) when is_integer(count) do
    %{kind: :text, text: "set #{count} #{pluralize(count, "container priority", "container priorities")}"}
  end

  def build(:limited_entries, nil), do: %{kind: :limited_entries}
  def build(:no_log, nil), do: %{kind: :text, text: "no log history"}
  def build(message_id, message_data), do: %{kind: :unknown, message_id: message_id, message_data: message_data}

  @spec status(nil | %{required(:status) => :started | :finished | :errored}) :: nil | status()
  def status(nil), do: nil
  def status(%{status: :started}), do: %{icon: "hero-command-line", text_color: "text-low-visibility"}
  def status(%{status: :finished}), do: %{icon: "hero-check-circle", text_color: "text-success-icon"}
  def status(%{status: :errored}), do: %{icon: "hero-exclamation-circle", text_color: "text-error-two"}

  defp pluralize(1, singular, _plural), do: singular
  defp pluralize(_count, _singular, plural), do: plural
  defp pluralize(count, singular), do: pluralize(count, singular, singular <> "s")

  defp flatten_container_changes(containers) do
    containers
    |> Enum.flat_map(fn {node, changes} ->
      Enum.map(changes, fn {container, status} -> {node, container, status} end)
    end)
  end

  defp refresh_changes(flattened) do
    flattened
    |> Enum.reject(fn {_node, _container, status} -> match?({:before, _}, status) end)
    |> Enum.sort()
  end

  defp refresh_counts(flattened) do
    Enum.reduce(
      flattened,
      %{new: 0, vanished: 0, started: 0, stopped: 0, errored: 0},
      fn
        {_node, _container, {:new, _}}, counts -> Map.update!(counts, :new, &(&1 + 1))
        {_node, _container, {:ok, :vanished}}, counts -> Map.update!(counts, :vanished, &(&1 + 1))
        {_node, _container, {:ok, true}}, counts -> Map.update!(counts, :started, &(&1 + 1))
        {_node, _container, {:ok, false}}, counts -> Map.update!(counts, :stopped, &(&1 + 1))
        {_node, _container, {:error, _}}, counts -> Map.update!(counts, :errored, &(&1 + 1))
        {_node, _container, _status}, counts -> counts
      end
    )
  end
end
