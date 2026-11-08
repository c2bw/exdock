defmodule Exdock.Server.Jobs.NodeRefreshSnapshot do
  @moduledoc """
  Typed result contract for one successful node refresh.

  The remote client reports container and image result sets together. Keeping
  that pair intact lets state persistence, progress logging, and tests share one
  explicit shape instead of passing selected pieces through ad-hoc maps.
  """

  alias Exdock.Protocol.Snapshot

  @type result_set(value) :: %{
          required(:ok) => [value],
          required(:errored) => list()
        }

  defstruct [:container_results, :image_results]

  @type t :: %__MODULE__{
          container_results: result_set(Snapshot.Container.t()),
          image_results: result_set(Snapshot.Image.t())
        }

  @spec new(result_set(Snapshot.Container.t()), result_set(Snapshot.Image.t())) :: t()
  def new(
        %{ok: containers, errored: container_errors} = container_results,
        %{ok: images, errored: image_errors} = image_results
      )
      when is_list(containers) and is_list(container_errors) and
             is_list(images) and is_list(image_errors) do
    %__MODULE__{
      container_results: container_results,
      image_results: image_results
    }
  end

  @spec containers(t()) :: [Snapshot.Container.t()]
  def containers(%__MODULE__{container_results: %{ok: containers}}), do: containers

  @spec images(t()) :: [Snapshot.Image.t()]
  def images(%__MODULE__{image_results: %{ok: images}}), do: images

  @spec container_errors(t()) :: list()
  def container_errors(%__MODULE__{container_results: %{errored: errors}}), do: errors

  @spec image_errors(t()) :: list()
  def image_errors(%__MODULE__{image_results: %{errored: errors}}), do: errors
end
