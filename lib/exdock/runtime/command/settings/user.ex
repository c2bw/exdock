defmodule Exdock.Runtime.Command.Settings.User do
  @moduledoc false

  @behaviour Exdock.Runtime.Command.Handler

  alias Exdock.Configuration
  alias Exdock.Runtime.Command.MutationExecutor
  alias Exdock.Runtime.Mutation

  @actions [:change_user_setting, :import_server_configuration]

  defstruct [:action, :data, :mutation]

  @type t :: %__MODULE__{
          action: :change_user_setting | :import_server_configuration,
          data: term(),
          mutation: Exdock.Runtime.Mutation.t() | nil
        }

  @spec user_setting(atom(), term()) :: t()
  def user_setting(key, value),
    do: command(:change_user_setting, {key, value})

  @spec import(Configuration.t()) :: t()
  def import(%Configuration{} = configuration),
    do: command(:import_server_configuration, configuration)

  @impl true
  def kind(%__MODULE__{action: action}) when action in @actions, do: action

  @impl true
  def normalize(
        %__MODULE__{
          action: :change_user_setting,
          data: {key, value}
        } = command
      ) do
    MutationExecutor.attach(command, Mutation.user_setting(key, value))
  end

  def normalize(
        %__MODULE__{
          action: :import_server_configuration,
          data: configuration
        } = command
      ) do
    MutationExecutor.attach(command, Mutation.import_configuration(configuration))
  end

  def normalize(%__MODULE__{}), do: {:error, :invalid_command}

  @impl true
  defdelegate execute(state, command), to: MutationExecutor

  defp command(action, data), do: %__MODULE__{action: action, data: data}
end
