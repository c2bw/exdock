defmodule Exdock.Domain.TagInfo do
  @moduledoc """
  Tag information from the remote registry.

  ## Fields
  - `tag`
  - `platform`: OCI platform this metadata was resolved for
  - `latest_digest`: digest in the remote registry
  - `latest_date`: date in the remote registry
  - `check_date`: remote data last fetch
  """
  alias Exdock.Datetime

  defstruct [
    :tag,
    :platform,
    :latest_digest,
    :latest_date,
    :check_date
  ]

  @type t :: %__MODULE__{
          tag: String.t(),
          platform: String.t(),
          latest_digest: String.t(),
          latest_date: DateTime.t(),
          check_date: DateTime.t() | nil
        }

  @spec new(String.t(), String.t(), String.t(), DateTime.t(), DateTime.t() | nil) ::
          t()
  def new(tag, platform, latest_digest, %DateTime{} = latest_date, check_date)
      when is_binary(tag) and is_binary(platform) and
             (is_nil(check_date) or is_struct(check_date)) do
    %__MODULE__{
      tag: tag,
      platform: platform,
      latest_digest: latest_digest,
      latest_date: latest_date,
      check_date: check_date
    }
  end

  @doc """
  Returns the default tag info for a new tag.
  """
  @spec default(String.t(), String.t()) :: t()
  def default(tag, platform) when is_binary(tag) and is_binary(platform),
    do: new(tag, platform, "", Datetime.unix_epoch(), nil)

  @doc false
  @spec from_persisted(map()) :: t()
  def from_persisted(%{
        tag: tag,
        platform: platform,
        latest_digest: digest,
        latest_date: latest_date,
        check_date: check_date
      }) do
    new(tag, platform, digest, latest_date, check_date)
  end
end
