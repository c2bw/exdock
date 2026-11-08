defmodule Exdock.Runtime.Port do
  @moduledoc false

  @spec validate_behaviour!(term(), module(), atom()) :: module()
  def validate_behaviour!(module, behaviour, label) when is_atom(behaviour) do
    Code.ensure_loaded!(behaviour)
    validate_module!(module, behaviour.behaviour_info(:callbacks), label)
  end

  @spec validate_module!(term(), [{atom(), arity()}], atom()) :: module()
  def validate_module!(module, callbacks, label)
      when is_atom(module) and is_list(callbacks) and is_atom(label) do
    loaded? = Code.ensure_loaded?(module)

    missing =
      Enum.reject(callbacks, fn {name, arity} ->
        loaded? and function_exported?(module, name, arity)
      end)

    case missing do
      [] -> module
      _callbacks -> raise ArgumentError, "invalid #{label} adapter #{inspect(module)}; missing #{inspect(missing)}"
    end
  end

  def validate_module!(module, _callbacks, label) when is_atom(label) do
    raise ArgumentError, "invalid #{label} adapter #{inspect(module)}; expected a module"
  end
end
