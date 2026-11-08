defmodule Exdock.Domain.Node.Settings do
  alias Exdock.URL
  alias Exdock.Domain.ImportFields

  @default_web_ui ""
  @import_fields [
    {"web_ui", :web_ui, &is_binary/1}
  ]

  defstruct [
    :web_ui
  ]

  @type t :: %__MODULE__{
          web_ui: String.t()
        }
  @spec new(String.t()) :: t()
  def new(web_ui) when is_binary(web_ui), do: %__MODULE__{web_ui: web_ui}

  @spec default() :: t()
  def default() do
    struct(__MODULE__, web_ui: @default_web_ui)
  end

  @spec set(t(), atom() | String.t(), term()) :: t()
  def set(%__MODULE__{} = settings, key, value) do
    case validate_setting(key, value) do
      {:ok, {:web_ui, value}} -> %{settings | web_ui: value}
      {:error, _reason} -> settings
    end
  end

  @doc false
  @spec setting_key(atom() | String.t()) :: {:ok, :web_ui} | :error
  def setting_key(:web_ui), do: {:ok, :web_ui}
  def setting_key("web_ui"), do: {:ok, :web_ui}
  def setting_key(_key), do: :error

  @doc false
  @spec validate_setting(term(), term()) ::
          {:ok, {:web_ui, String.t()}}
          | {:error, {:unknown_node_setting, term()} | {:invalid_node_setting_value, :web_ui}}
  def validate_setting(key, value) do
    case setting_key(key) do
      {:ok, :web_ui} when is_binary(value) ->
        {:ok, {:web_ui, URL.normalize_external(value)}}

      {:ok, :web_ui} ->
        {:error, {:invalid_node_setting_value, :web_ui}}

      :error ->
        {:error, {:unknown_node_setting, key}}
    end
  end

  @doc false
  @spec from_import(map()) :: t()
  def from_import(%{} = unsafe) do
    default()
    |> ImportFields.apply_fields(unsafe, @import_fields, &set/3)
  end
end
