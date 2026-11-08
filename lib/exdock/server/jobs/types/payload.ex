defmodule Exdock.Server.Jobs.Payload do
  @moduledoc """
  Shared lifecycle payload vocabulary.

  Job start metadata uses dedicated structs. Updates and results also include
  decoded client wire values, so their types describe the supported shapes at
  that trust boundary without weakening every lifecycle struct to `any()`.
  """

  alias Exdock.Domain.Repository.Release
  alias Exdock.Server.Jobs.NodeRefreshSnapshot
  alias Exdock.Server.Jobs.Payload

  @type job_data ::
          nil
          | Payload.ContainerAction.t()
          | Payload.ImageAction.t()
          | Payload.NodeRefresh.t()
          | Payload.RegistryFetch.t()
          | Payload.ReleasesFetch.t()
          | map()

  @type parameter :: nil | boolean() | number() | String.t() | atom() | map() | list() | tuple()

  @type update ::
          String.t()
          | {atom(), String.t()}
          | NodeRefreshSnapshot.t()
          | map()

  @type result ::
          nil
          | :done
          | String.t()
          | map()
          | list()
          | {String.t(), [String.t()]}
          | {map(), map()}
          | {:done, [Release.t()]}

  @type message :: String.t() | number() | atom() | map() | list() | tuple()
  @type package_log :: {non_neg_integer(), [String.t()]} | {non_neg_integer(), [String.t()], boolean()}
  @type error :: nil | atom() | String.t() | map() | tuple() | Exception.t()
end
