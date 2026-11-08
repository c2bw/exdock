defmodule Exdock.Server.State.Domain do
  @moduledoc """
  Registry and internal dispatch boundary for authoritative state domains.

  Domain atoms are the stable vocabulary used by runtime mutations and events.
  Storage modules remain implementation details behind this registry.
  """

  alias Exdock.Server.State
  alias Exdock.Server.State.Domains
  alias Exdock.Runtime.DomainCatalog
  alias Exdock.Runtime.Mutation
  alias Exdock.Runtime.MutationContract
  alias Exdock.Server.State.Change.Plan

  @modules %{
    settings: Domains.Settings,
    tags: Domains.Tags,
    repositories: Domains.Repositories,
    nodes: Domains.Nodes,
    images: Domains.Images,
    containers: Domains.Containers
  }

  @type name :: :settings | :tags | :repositories | :nodes | :images | :containers

  @spec names() :: [name()]
  defdelegate names(), to: DomainCatalog, as: :domains

  @spec valid?(term()) :: boolean()
  def valid?(domain), do: Mutation.valid_domain?(domain)

  @spec module(name()) :: module()
  def module(domain), do: Map.fetch!(@modules, domain)

  @spec name(module()) :: name()
  def name(module) when is_atom(module) do
    Enum.find_value(@modules, fn
      {domain, ^module} -> domain
      _entry -> nil
    end) || raise ArgumentError, "unknown state domain module: #{inspect(module)}"
  end

  @spec cluster_names() :: [name()]
  defdelegate cluster_names(), to: DomainCatalog, as: :cluster_domains

  @spec plan(name(), State.t(), Mutation.t()) :: Plan.t()
  def plan(domain, %State{} = state, %Mutation{domain: domain, action: action} = mutation) do
    case MutationContract.normalize_payload(domain, action, mutation.data) do
      {:ok, data} ->
        module(domain).plan(state, %{mutation | data: data})

      {:error, _reason} ->
        if DomainCatalog.valid_action?(domain, action) do
          Plan.invalid_mutation_payload(mutation)
        else
          Plan.immediate({:error, {:unknown_state_action, domain, action}})
        end
    end
  end

  def plan(domain, %State{}, %Mutation{domain: mutation_domain}) do
    Plan.immediate({:error, {:mutation_domain_mismatch, domain, mutation_domain}})
  end

  @spec reload(name(), State.t(), name()) :: State.t()
  def reload(:containers, %State{} = state, :settings),
    do: Domains.Containers.reload_settings(state)

  def reload(domain, %State{} = state, _changed_domain) do
    module(domain).reload(state)
  end

  @spec broadcast_payload(name(), State.t()) :: {term(), keyword()}
  def broadcast_payload(domain, %State{} = state), do: module(domain).broadcast(state)

  @spec dependents(name(), atom()) :: [name()]
  defdelegate dependents(changed_domain, action), to: DomainCatalog
end
