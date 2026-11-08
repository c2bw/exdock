defmodule ExdockWeb.PageLive.Utils.ModalState do
  @moduledoc false

  @spec render?(map(), term()) :: boolean()
  def render?(modals, modal_id) when is_map(modals), do: Map.has_key?(modals, modal_id)
end
