defmodule Exdock.Runtime.MutationContract.Settings do
  @moduledoc false

  alias Exdock.Configuration
  alias Exdock.Domain
  alias Exdock.Runtime.Mutation.Payload

  @spec normalize(term(), term()) :: {:ok, term()} | {:error, term()}
  def normalize(:user_setting, {key, value}),
    do: normalize(:user_setting, %Payload.UserSetting{key: key, value: value})

  def normalize(:user_setting, %Payload.UserSetting{key: key, value: value}) do
    with {:ok, {key, value}} <- Domain.UserSettings.validate_setting(key, value) do
      {:ok, %Payload.UserSetting{key: key, value: value}}
    end
  end

  def normalize(:import, %Configuration{} = configuration),
    do: {:ok, %Payload.ConfigurationImport{configuration: configuration}}

  def normalize(
        :import,
        %Payload.ConfigurationImport{configuration: %Configuration{}} = payload
      ),
      do: {:ok, payload}

  def normalize(action, _payload), do: invalid(action)

  defp invalid(action), do: {:error, {:invalid_mutation_payload, :settings, action}}
end
