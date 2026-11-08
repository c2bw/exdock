defmodule ExdockWeb.PageLive.Utils.IdUtils do
  @spec create_id(String.t()) :: String.t()
  def create_id(s) do
    :crypto.hash(:sha, s)
    |> Base.url_encode64(padding: false)
    |> to_safe_id()
  end

  defp to_safe_id(id_string), do: "id-#{id_string}"

  # Functions for IDs that are referenced in multiple places

  @spec container_manager_id(Exdock.NodeId.t(), String.t()) :: String.t()
  def container_manager_id(node, container_name), do: create_id("container_manager_#{node}_#{container_name}")

  @spec node_summary_div_id(Exdock.NodeId.t()) :: String.t()
  def node_summary_div_id(node), do: create_id("node_summary_div_#{node}")
end
