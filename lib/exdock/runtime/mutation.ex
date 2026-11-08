defmodule Exdock.Runtime.Mutation do
  @moduledoc "A validated mutation request for one runtime state domain."

  alias Exdock.Runtime.DomainCatalog
  alias Exdock.Runtime.MutationContract
  alias Exdock.Runtime.Mutation.Payload
  alias Exdock.Domain
  alias Exdock.Domain.Container.Resources.Record

  @enforce_keys [:domain, :action, :data]
  defstruct [:domain, :action, :data]

  @type domain :: DomainCatalog.domain()
  @type action :: DomainCatalog.action()
  @type payload ::
          Payload.UserSetting.t()
          | Payload.ConfigurationImport.t()
          | Payload.TagsInfo.t()
          | Payload.RepositoryReleases.t()
          | Payload.NodeSetting.t()
          | Payload.ImageDeleteLock.t()
          | Payload.ImageRepositories.t()
          | Payload.ContainerAutoUpdate.t()
          | Payload.ContainerResources.t()
          | Payload.ContainerLogs.t()
          | Payload.ContainerPriorities.t()

  @type t :: %__MODULE__{domain: domain(), action: action(), data: payload()}

  @spec domains() :: [domain()]
  def domains, do: DomainCatalog.domains()

  @spec valid_domain?(term()) :: boolean()
  def valid_domain?(domain), do: DomainCatalog.valid?(domain)

  @spec valid_action?(term(), term()) :: boolean()
  def valid_action?(domain, action), do: DomainCatalog.valid_action?(domain, action)

  @spec user_setting(term(), term()) :: {:ok, t()} | {:error, term()}
  def user_setting(key, value),
    do: build(:settings, :user_setting, %Payload.UserSetting{key: key, value: value})

  @spec import_configuration(term()) :: {:ok, t()} | {:error, term()}
  def import_configuration(configuration),
    do:
      build(:settings, :import, %Payload.ConfigurationImport{
        configuration: configuration
      })

  @spec tags_info([Domain.TagInfo.t()]) :: {:ok, t()} | {:error, term()}
  def tags_info(tags), do: build(:tags, :tags_info, %Payload.TagsInfo{tags: tags})

  @spec repository_releases(list()) :: {:ok, t()} | {:error, term()}
  def repository_releases(results),
    do:
      build(:repositories, :repository_releases, %Payload.RepositoryReleases{
        results: results
      })

  @spec node_setting(term(), term(), term()) :: {:ok, t()} | {:error, term()}
  def node_setting(node, key, value),
    do: build(:nodes, :setting, %Payload.NodeSetting{node: node, key: key, value: value})

  @spec image_delete_lock(String.t(), String.t(), boolean()) :: {:ok, t()} | {:error, term()}
  def image_delete_lock(node, id, locked),
    do:
      build(:images, :delete_lock, %Payload.ImageDeleteLock{
        node: node,
        id: id,
        locked?: locked
      })

  @spec image_repository_url(String.t(), String.t()) :: {:ok, t()} | {:error, term()}
  def image_repository_url(image, url),
    do:
      build(:images, :repository_url, %Payload.ImageRepositories{
        overrides: [%Payload.ImageRepository{image: image, url: url}]
      })

  @spec image_repository_urls([{String.t(), String.t()}]) :: {:ok, t()} | {:error, term()}
  def image_repository_urls(overrides),
    do: build(:images, :repository_url, %Payload.ImageRepositories{overrides: overrides})

  @spec container_auto_update(String.t(), String.t(), atom()) :: {:ok, t()} | {:error, term()}
  def container_auto_update(node, name, policy),
    do:
      build(:containers, :auto_update, %Payload.ContainerAutoUpdate{
        node: node,
        name: name,
        policy: policy
      })

  @spec container_resources(String.t(), String.t(), Record.t()) :: {:ok, t()} | {:error, term()}
  def container_resources(node, id, resources),
    do:
      build(:containers, :set_resources, %Payload.ContainerResources{
        node: node,
        id: id,
        resources: resources
      })

  @spec container_logs(String.t(), String.t(), [String.t()], DateTime.t()) ::
          {:ok, t()} | {:error, term()}
  def container_logs(node, id, logs, occurred_at),
    do:
      build(:containers, :set_logs, %Payload.ContainerLogs{
        node: node,
        id: id,
        logs: logs,
        occurred_at: occurred_at
      })

  @spec container_priority(String.t(), String.t(), integer()) :: {:ok, t()} | {:error, term()}
  def container_priority(node, name, priority),
    do:
      build(:containers, :priority, %Payload.ContainerPriorities{
        priorities: [
          %Payload.ContainerPriority{node: node, name: name, priority: priority}
        ]
      })

  @spec container_priorities([{String.t(), String.t(), integer()}]) :: {:ok, t()} | {:error, term()}
  def container_priorities(priorities),
    do: build(:containers, :priority, %Payload.ContainerPriorities{priorities: priorities})

  @spec user_setting!(term(), term()) :: t()
  def user_setting!(key, value), do: unwrap!(user_setting(key, value))

  @spec tags_info!([Domain.TagInfo.t()]) :: t()
  def tags_info!(tags), do: unwrap!(tags_info(tags))

  @spec repository_releases!(list()) :: t()
  def repository_releases!(results), do: unwrap!(repository_releases(results))

  @spec container_resources!(String.t(), String.t(), Record.t()) :: t()
  def container_resources!(node, id, resources), do: unwrap!(container_resources(node, id, resources))

  @spec container_logs!(String.t(), String.t(), [String.t()], DateTime.t()) :: t()
  def container_logs!(node, id, logs, occurred_at), do: unwrap!(container_logs(node, id, logs, occurred_at))

  @doc false
  @spec build(term(), term(), term()) :: {:ok, t()} | {:error, term()}
  def build(domain, action, data) when is_atom(action) do
    cond do
      not valid_domain?(domain) ->
        {:error, {:unknown_state_domain, domain}}

      not valid_action?(domain, action) ->
        {:error, {:unknown_state_action, domain, action}}

      true ->
        with {:ok, data} <- MutationContract.normalize_payload(domain, action, data) do
          {:ok, %__MODULE__{domain: domain, action: action, data: data}}
        end
    end
  end

  def build(_domain, action, _data), do: {:error, {:invalid_mutation_action, action}}

  defp unwrap!({:ok, %__MODULE__{} = mutation}), do: mutation
  defp unwrap!({:error, reason}), do: raise(ArgumentError, inspect(reason))
end
