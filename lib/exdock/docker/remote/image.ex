defmodule Exdock.Docker.Remote.Image do
  @moduledoc """
  Remote registry image metadata helpers backed by `regc`.

  Local Docker Engine APIs cannot answer all registry questions without pulling
  an image. This module uses `regc` to validate remote manifests and image
  configurations for the platform reported by the node running the image.

  Digests intentionally come from `root_ref`. This preserves the previous
  `regctl image digest --list` behavior: a multi-platform tag is represented by
  its manifest-list digest rather than a platform-specific child digest.
  """

  require Logger
  alias Exdock.Docker.Remote.RegistryClient
  alias Regc.Oci.Error

  @doc """
  Return the remote root digest for an image tag and platform.
  """
  @spec digest(String.t(), String.t()) :: String.t()
  def digest(image_tag, platform) when is_binary(image_tag) and is_binary(platform) do
    RegistryClient.get()
    |> check_image(image_tag, platform: platform)
    |> digest_result()
  end

  @doc false
  @spec digest_result({:ok, map()} | {:error, Error.t()}) :: String.t()
  def digest_result(result) do
    case result do
      {:ok, %{root_ref: %{digest: digest}}} when is_binary(digest) ->
        digest

      {:error, %Error{} = error} ->
        raise error
    end
  end

  @doc """
  Return the remote creation date for an image tag and platform.

  Falls back to the Unix epoch when the verified image configuration omits its
  creation date or the returned timestamp cannot be parsed, allowing callers to
  continue comparing images with a known sentinel.
  """
  @spec creation_date(String.t(), String.t()) :: DateTime.t()
  def creation_date(image_tag, platform) when is_binary(image_tag) and is_binary(platform) do
    RegistryClient.get()
    |> image_created(image_tag, platform: platform)
    |> creation_date_result()
  end

  @doc false
  @spec creation_date_result({:ok, String.t() | nil} | {:error, Error.t()}) :: DateTime.t()
  def creation_date_result(result) do
    case result do
      {:ok, created} ->
        parse_creation_date(created)

      {:error, %Error{} = error} ->
        raise error
    end
  end

  defp parse_creation_date(created) when is_binary(created) do
    case DateTime.from_iso8601(created) do
      {:ok, datetime, _offset} -> datetime
      {:error, reason} -> creation_date_fallback(reason)
    end
  end

  defp parse_creation_date(nil), do: creation_date_fallback(:missing_created)

  defp creation_date_fallback(reason) do
    Logger.error("Remote Image: could not parse date: #{inspect(reason)}")
    DateTime.from_unix!(0)
  end

  # Regc's overloaded facade is mis-inferred by Dialyzer on OTP 29. A dynamic
  # call at this boundary preserves Regc's public contract without disabling
  # analysis for the application functions that consume it.
  @spec check_image(Regc.Client.t(), String.t(), keyword()) ::
          {:ok, Regc.Oci.Image.Resolved.t()} | {:error, Error.t()}
  defp check_image(client, image_tag, opts),
    do: apply(Regc, :check_image, [client, image_tag, opts])

  @spec image_created(Regc.Client.t(), String.t(), keyword()) ::
          {:ok, String.t() | nil} | {:error, Error.t()}
  defp image_created(client, image_tag, opts),
    do: apply(Regc, :image_created, [client, image_tag, opts])
end
