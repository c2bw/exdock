defmodule Exdock.Server.Jobs.Local.Releases.HTTPRequest do
  @moduledoc """
  Provider-specific HTTP request description for release APIs.

  The request struct stores both the original repository URL and the provider
  API URL so results and errors can be mapped back to Exdock repository state.
  """
  alias Exdock.Server.Jobs.Local.Releases.{Provider, ResponseMapper}
  alias Exdock.Domain.Repository.Release

  @type t :: %__MODULE__{
          provider: atom(),
          releases_url: String.t(),
          bearer_token: String.t() | nil,
          repo_name: String.t(),
          repo_url: String.t()
        }

  @type result ::
          {:ok, String.t(), [Release.t()]}
          | {:error, String.t(), term()}

  @type transport ::
          (String.t(), keyword() -> {:ok, Req.Response.t()} | {:error, term()})

  @rate_limited_statuses [403, 429]

  def providers(), do: Provider.hosts()

  defstruct [
    :provider,
    :releases_url,
    :bearer_token,
    :repo_name,
    :repo_url
  ]

  @spec supported_provider?(String.t()) :: boolean()
  def supported_provider?(repository_url), do: Provider.supported?(repository_url)

  @doc """
  Create a new HTTPRequest struct for a repository.

  NOTE: only pass repositories of supported providers.
  """
  @spec new(String.t(), keyword()) :: t()
  def new(repository_url, opts \\ []) when is_binary(repository_url) and is_list(opts) do
    case Provider.resolve(repository_url) do
      :unsupported ->
        raise "Unsupported provider for repository: #{repository_url}"

      {:ok, provider, repo_name} ->
        %__MODULE__{
          provider: provider,
          releases_url: Provider.releases_url(provider, repo_name),
          bearer_token: bearer_token(provider, opts),
          repo_name: repo_name,
          repo_url: repository_url
        }
    end
  end

  defp bearer_token(provider, opts) do
    token_provider = Keyword.get(opts, :token_provider, &Provider.bearer_token/1)
    token_provider.(provider)
  end

  @doc """
  Execute the HTTP request and return parsed releases or a provider error.

  Rate limits are normalized across providers so callers can update repository
  status without inspecting raw HTTP responses.
  """
  @spec request(t()) :: result()
  def request(%__MODULE__{} = request) do
    request(request, &Req.get/2)
  end

  @doc """
  Execute the request through an explicit transport.

  The transport receives the provider API URL and Req options, allowing callers
  to exercise response normalization without performing a network request.
  """
  @spec request(t(), transport()) :: result()
  def request(%__MODULE__{} = request, transport) when is_function(transport, 2) do
    request.releases_url
    |> transport.(request_options(request))
    |> normalize_request_result(request)
  end

  defp request_options(%__MODULE__{bearer_token: nil}), do: []

  defp request_options(%__MODULE__{bearer_token: token}) when is_binary(token),
    do: [auth: {:bearer, token}]

  # Request results are normalized so callers do not need provider-specific HTTP
  # knowledge.
  defp normalize_request_result({:ok, %Req.Response{status: 200, body: body}}, request),
    do: {:ok, request.repo_url, parse(request, body, DateTime.utc_now())}

  defp normalize_request_result({:ok, %Req.Response{status: status}}, request)
       when status in @rate_limited_statuses,
       do: {:error, request.repo_url, :rate_limit}

  defp normalize_request_result({:ok, %Req.Response{status: 404}}, request),
    do: {:error, request.repo_url, :not_found}

  defp normalize_request_result({:error, error}, request), do: {:error, request.repo_url, error}

  defp normalize_request_result({:ok, %Req.Response{status: status}}, request),
    do: {:error, request.repo_url, {:unexpected_status, status}}

  @doc """
  Normalize a provider response body into Exdock release structs.

  GitHub and GitLab expose release metadata with different payload keys. A shared
  field-path map keeps parsing in one place and guarantees each provider is
  mapped to the same internal shape.
  """
  @spec parse(t(), list(map())) :: [Release.t()]
  def parse(%__MODULE__{} = request, body) when is_list(body) do
    parse(request, body, DateTime.utc_now())
  end

  @spec parse(t(), list(map()), DateTime.t()) :: [Release.t()]
  def parse(%__MODULE__{} = request, body, %DateTime{} = fetched_at) when is_list(body) do
    ResponseMapper.parse(request.provider, request.repo_name, request.repo_url, body, fetched_at)
  end
end
