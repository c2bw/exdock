defmodule Exdock.ReadModel.Repository do
  @moduledoc """
  Public repository projection consumed by LiveViews.
  """

  alias Exdock.ReadModel.{Release, RepositoryPage}

  defstruct [:url, :page, :provider_icon, :label, releases: []]

  @type t :: %__MODULE__{
          url: String.t(),
          page: RepositoryPage.t(),
          provider_icon: String.t() | nil,
          label: String.t(),
          releases: [Release.t()]
        }

  @spec from_domain(map()) :: t()
  def from_domain(%{url: url, metadata: metadata, releases: domain_releases}) do
    releases = Enum.map(domain_releases || [], &Release.from_domain/1)

    %__MODULE__{
      url: url,
      page: RepositoryPage.from_domain(metadata),
      provider_icon: releases |> List.first() |> provider_icon(),
      label: repository_label(url),
      releases: releases
    }
  end

  @spec default(String.t()) :: t()
  def default(url) when is_binary(url) do
    %__MODULE__{
      url: url,
      page: %RepositoryPage{},
      provider_icon: nil,
      label: repository_label(url),
      releases: []
    }
  end

  defp provider_icon(nil), do: nil
  defp provider_icon(%Release{provider_icon: provider_icon}), do: provider_icon

  defp repository_label(url) do
    url
    |> URI.parse()
    |> then(fn uri -> Enum.join(Enum.reject([uri.host, uri.path], &is_nil/1), "") end)
    |> String.trim_leading("/")
    |> String.downcase()
  end
end
