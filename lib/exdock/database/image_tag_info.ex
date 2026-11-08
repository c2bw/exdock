defmodule Exdock.Database.ImageTagInfo do
  use Ecto.Schema
  import Ecto.Query
  import Ecto.Changeset

  @persisted_fields [:tag, :platform, :latest_digest, :latest_date, :check_date]

  @type t :: %Exdock.Database.ImageTagInfo{
          tag: String.t(),
          platform: String.t(),
          latest_digest: String.t(),
          latest_date: DateTime.t(),
          check_date: DateTime.t() | nil
        }

  @doc """
    The ImageTagInfo schema stores the data for a tag:
    - tag: A tag
    - platform: OCI platform associated with this metadata
    - latest_digest: The latest known digest of the remote image
    - latest_date: The latest known date of the remote image
    - check_date: The date when the image was last checked
  """
  @primary_key false
  schema "image_tag_info" do
    field(:tag, :string, primary_key: true)
    field(:platform, :string, primary_key: true)
    field(:latest_digest, :string)
    field(:latest_date, :utc_datetime)
    field(:check_date, :utc_datetime)
  end

  @spec new(map()) :: t()
  def new(%{
        tag: tag,
        platform: platform,
        latest_digest: latest_digest,
        latest_date: latest_date,
        check_date: check_date
      }) do
    # The schema uses :utc_datetime, which rejects microseconds. Normalize at
    # the runtime-to-database boundary so all insert/update callers share it.
    %__MODULE__{
      tag: tag,
      platform: platform,
      latest_digest: latest_digest,
      latest_date: truncate_datetime(latest_date),
      check_date: truncate_datetime(check_date)
    }
  end

  @doc """
    Retrieve the info of a tag.
  """
  @spec by_tag_and_platform(String.t(), String.t()) :: t() | nil
  def by_tag_and_platform(tag, platform)
      when is_binary(tag) and is_binary(platform) do
    Exdock.Repo.get_by(Exdock.Database.ImageTagInfo,
      tag: tag,
      platform: platform
    )
  end

  @doc """
    Retrieve all tags info.
  """
  @spec load_all() :: [t()]
  def load_all do
    from(i in Exdock.Database.ImageTagInfo, select: i)
    |> Exdock.Repo.all()
  end

  @doc """
    Inserts the tag info.
  """
  @spec insert(t()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def insert(%__MODULE__{} = info, opts \\ []) do
    opts = opts |> Keyword.put_new(:on_conflict, :replace_all)

    info
    |> image_tag_info_changeset(%{})
    |> Exdock.Repo.insert(opts)
  end

  @doc """
    Update info of a tag.
  """
  @spec update(t()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def update(%__MODULE__{} = info) do
    info
    |> image_tag_info_changeset(%{})
    |> Exdock.Repo.insert(
      on_conflict: {:replace_all_except, [:tag, :platform]},
      conflict_target: [:tag, :platform]
    )
  end

  defp image_tag_info_changeset(info, params) do
    info
    |> cast(params, @persisted_fields)
    |> validate_required([:tag, :platform])
    |> truncate_dates()
  end

  defp truncate_dates(changeset) do
    changeset
    |> put_change(:latest_date, truncate_datetime(get_field(changeset, :latest_date)))
    |> put_change(:check_date, truncate_datetime(get_field(changeset, :check_date)))
  end

  defp truncate_datetime(nil), do: nil
  defp truncate_datetime(%DateTime{} = datetime), do: DateTime.truncate(datetime, :second)
end
