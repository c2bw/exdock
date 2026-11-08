defmodule Exdock.Domain.ImportFields do
  @moduledoc """
  Shared helpers for importing persisted UI/server settings from maps.

  Server configuration imports are intentionally permissive: a malformed field
  should fall back to the current/default value instead of aborting the whole
  import.  Callers pass an explicit field list so only known keys can update a
  struct, which keeps the data flow easy to audit and avoids creating atoms from
  arbitrary input.
  """

  @type field :: {String.t(), atom(), (term() -> boolean())}

  @doc """
  Applies valid fields from `unsafe` to `settings`.

  Each field is `{external_key, internal_field, validator}`. Missing and invalid
  values are ignored. `setter` is usually the module's private `set/3`, so field
  specific normalization remains near the struct definition.
  """
  @spec apply_fields(struct(), map(), [field()], (struct(), atom(), term() -> struct())) :: struct()
  def apply_fields(settings, unsafe, fields, setter)
      when is_map(unsafe) and is_list(fields) and is_function(setter, 3) do
    Enum.reduce(fields, settings, fn field_spec, acc ->
      apply_field(acc, unsafe, field_spec, setter)
    end)
  end

  defp apply_field(settings, unsafe, field_spec, setter) do
    case imported_field(field_spec, unsafe) do
      {:ok, field, value} -> setter.(settings, field, value)
      :error -> settings
    end
  end

  defp imported_field({external_key, field, validator}, unsafe)
       when is_binary(external_key) and is_atom(field) and is_function(validator, 1) and is_map(unsafe) do
    with {:ok, value} <- fetch_import_value(unsafe, external_key),
         :ok <- validate_import_value(value, validator) do
      {:ok, field, value}
    end
  end

  defp fetch_import_value(unsafe, external_key), do: Map.fetch(unsafe, external_key)

  defp validate_import_value(value, validator) do
    if validator.(value), do: :ok, else: :error
  end
end
