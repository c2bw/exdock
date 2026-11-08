defmodule Exdock.Runtime.MutationContract do
  @moduledoc """
  Static vocabulary and domain-routed payload validation for runtime mutations.

  The catalog remains centralized while each domain owns its payload shapes and
  legacy input normalization in a focused normalizer module.
  """

  alias Exdock.Runtime.MutationContract

  @contracts [
    settings: [:user_setting, :import],
    tags: [:tags_info],
    repositories: [:repository_releases],
    nodes: [:setting],
    images: [:delete_lock, :repository_url],
    containers: [:auto_update, :set_resources, :set_logs, :priority]
  ]

  @domains Keyword.keys(@contracts)
  @actions_by_domain Map.new(@contracts)

  @type domain :: :settings | :tags | :repositories | :nodes | :images | :containers
  @type action ::
          :user_setting
          | :import
          | :tags_info
          | :repository_releases
          | :setting
          | :delete_lock
          | :repository_url
          | :auto_update
          | :set_resources
          | :set_logs
          | :priority

  @spec domains() :: [domain()]
  def domains, do: @domains

  @spec valid_domain?(term()) :: boolean()
  def valid_domain?(domain), do: domain in @domains

  @spec actions(domain()) :: [action()]
  def actions(domain), do: Map.fetch!(@actions_by_domain, domain)

  @spec valid_action?(term(), term()) :: boolean()
  def valid_action?(domain, action) do
    case Map.fetch(@actions_by_domain, domain) do
      {:ok, actions} -> action in actions
      :error -> false
    end
  end

  @spec normalize_payload(term(), term(), term()) :: {:ok, term()} | {:error, term()}
  def normalize_payload(:settings, action, payload),
    do: MutationContract.Settings.normalize(action, payload)

  def normalize_payload(:tags, action, payload),
    do: MutationContract.Tags.normalize(action, payload)

  def normalize_payload(:repositories, action, payload),
    do: MutationContract.Repositories.normalize(action, payload)

  def normalize_payload(:nodes, action, payload),
    do: MutationContract.Nodes.normalize(action, payload)

  def normalize_payload(:images, action, payload),
    do: MutationContract.Images.normalize(action, payload)

  def normalize_payload(:containers, action, payload),
    do: MutationContract.Containers.normalize(action, payload)

  def normalize_payload(domain, action, _payload),
    do: {:error, {:invalid_mutation_payload, domain, action}}

  @spec valid_payload?(term(), term(), term()) :: boolean()
  def valid_payload?(domain, action, payload),
    do: match?({:ok, _normalized_payload}, normalize_payload(domain, action, payload))
end
