defmodule Exdock.Server.Jobs.Local.Registry.RemoteMetadata do
  @moduledoc """
  Resolves digest and creation metadata for one remote image tag.

  Creation dates are fetched by immutable digest when a tag is new or its digest changed.
  """

  alias Exdock.Docker
  alias Exdock.Domain.TagInfo
  alias Exdock.Protocol.ImageReference

  @type digest_lookup :: (String.t(), String.t() -> String.t())
  @type creation_date_lookup :: (String.t(), String.t() -> DateTime.t())

  @spec fetch(String.t(), String.t(), TagInfo.t() | nil) :: {String.t(), DateTime.t()}
  def fetch(image_tag, platform, previous_tag_info) do
    fetch(
      image_tag,
      platform,
      previous_tag_info,
      &Docker.Remote.Image.digest/2,
      &Docker.Remote.Image.creation_date/2
    )
  end

  @doc false
  @spec fetch(
          String.t(),
          String.t(),
          TagInfo.t() | nil,
          digest_lookup(),
          creation_date_lookup()
        ) :: {String.t(), DateTime.t()}
  def fetch(image_tag, platform, previous_tag_info, digest_lookup, creation_date_lookup)
      when is_binary(image_tag) and is_binary(platform) and is_function(digest_lookup, 2) and
             is_function(creation_date_lookup, 2) do
    remote_digest = digest_lookup.(image_tag, platform)

    remote_date =
      remote_date(
        image_tag,
        platform,
        previous_tag_info,
        remote_digest,
        creation_date_lookup
      )

    {remote_digest, remote_date}
  end

  defp remote_date(image_tag, platform, nil, remote_digest, creation_date_lookup),
    do: creation_date(image_tag, platform, remote_digest, creation_date_lookup)

  defp remote_date(
         image_tag,
         platform,
         %TagInfo{latest_digest: latest_digest},
         remote_digest,
         creation_date_lookup
       )
       when remote_digest != latest_digest,
       do: creation_date(image_tag, platform, remote_digest, creation_date_lookup)

  defp remote_date(
         _image_tag,
         _platform,
         %TagInfo{latest_date: latest_date},
         _remote_digest,
         _creation_date_lookup
       ),
       do: latest_date

  defp creation_date(image_tag, platform, digest, creation_date_lookup) do
    (ImageReference.repository(image_tag) <> "@" <> digest)
    |> creation_date_lookup.(platform)
    |> DateTime.truncate(:second)
  end
end
