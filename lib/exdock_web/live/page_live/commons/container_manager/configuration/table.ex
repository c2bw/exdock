defmodule ExdockWeb.Commons.ContainerManager.Configuration.Table do
  @moduledoc false

  use ExdockWeb, :html

  alias Exdock.Datetime

  attr :id, :string, required: true
  attr :core, :any, required: true
  attr :clock_now, :any, required: true

  def render(assigns) do
    ~H"""
    <div class="ms-1 mt-0 mb-2 overflow-auto rounded-lg bg-primary font-mono">
      <table class="m-0 w-full table-auto rounded text-center font-mono">
        <tbody class="first-row-divider-subtle divide-y divide-tertiary whitespace-nowrap">
          <tr class="pt-1 text-left leading-6 text-high-visibility">
            <td class="ps-2 text-low-visibility">Created</td>
            <td class="ps-2 text-xs">
              {@core.configuration.created |> Datetime.from_string()}
            </td>
          </tr>

          <tr class="pt-1 text-left leading-6 text-high-visibility">
            <%= if @core.is_running do %>
              <td class="ps-2 text-low-visibility">Started</td>
              <td class="ps-2 text-xs">
                {@core.state.started_at |> Datetime.as_string()}
              </td>
            <% else %>
              <td class="ps-2 text-low-visibility">Stopped</td>
              <td class="ps-2 text-xs">
                {@core.state.finished_at |> Datetime.as_string()}
              </td>
            <% end %>
          </tr>

          <tr class="pt-1 text-left leading-6 text-high-visibility">
            <td class="ps-2 text-low-visibility">Uptime</td>
            <td id={@id <> "-uptime"} class="ps-2 text-xs">
              <%= if @core.is_running do %>
                {@core.state.started_at |> Datetime.elapsed_since(@clock_now)}
              <% end %>
            </td>
          </tr>

          <tr class="pt-1 text-left leading-6 text-high-visibility">
            <td class="ps-2 text-low-visibility">Restart</td>
            <td class="ps-2 text-xs">
              {value(@core.configuration.restartpolicy, "Name", :Name)}
            </td>
          </tr>

          <tr class="pt-1 text-left leading-6 text-high-visibility">
            <td class="ps-2 text-low-visibility">Image</td>
            <td class="ps-2 text-xs">
              {@core.configuration.image_name_with_id}
            </td>
          </tr>

          <tr class="pt-1 text-left leading-6 text-high-visibility">
            <td class="ps-2 text-low-visibility">Size</td>
            <td class="ps-2 text-xs">{@core.image_size_human}</td>
          </tr>

          <tr class="pt-1 text-left leading-6 text-high-visibility">
            <td class="ps-2 text-low-visibility">Env</td>
            <td class="ps-2 text-xs">
              <ul class="first-divider-subtle divide-y divide-secondary">
                <li :for={env <- @core.configuration.env}>
                  <p class="overflow-hidden text-ellipsis">{env}</p>
                </li>
              </ul>
            </td>
          </tr>

          <tr class="pt-1 text-left leading-6 text-high-visibility">
            <td class="ps-2 text-low-visibility">CMD</td>
            <td class="ps-2 text-xs">{@core.configuration.cmd}</td>
          </tr>

          <tr class="pt-1 text-left leading-6 text-high-visibility">
            <td class="ps-2 tracking-tight text-low-visibility">Entrypoint</td>
            <td class="ps-2 text-xs">{@core.configuration.entrypoint}</td>
          </tr>

          <tr class="pt-1 text-left leading-6 text-high-visibility">
            <td class="ps-2 text-low-visibility">Ports</td>
            <td class="ps-2 text-xs">
              <ul class="first-divider-subtle divide-y divide-secondary">
                <%= for {container_port, host_ports} <- @core.configuration.ports || [] do %>
                  <li :for={host <- host_ports || []}>
                    <p class="overflow-hidden text-ellipsis">
                      {format_port(host, container_port)}
                    </p>
                  </li>
                <% end %>
              </ul>
            </td>
          </tr>

          <tr class="pt-1 text-left leading-6 text-high-visibility">
            <td class="ps-2 text-low-visibility">Binds</td>
            <td class="ps-2 text-xs">
              <ul class="first-divider-subtle divide-y divide-secondary">
                <li :for={bind <- @core.configuration.binds || []}>
                  <p class="overflow-hidden text-ellipsis">{bind}</p>
                </li>
              </ul>
            </td>
          </tr>

          <tr class="pt-1 text-left leading-6 text-high-visibility">
            <td class="ps-2 text-low-visibility">HostName</td>
            <td class="ps-2 text-xs">{@core.configuration.hostname}</td>
          </tr>

          <tr class="pt-1 text-left leading-6 text-high-visibility">
            <td class="ps-2 text-low-visibility">Networks</td>
            <td class="ps-2 text-xs">
              <ul class="first-divider-subtle divide-y divide-secondary">
                <li :for={{name, network} <- @core.configuration.networks || %{}}>
                  <p class="overflow-hidden text-ellipsis">
                    {format_network(name, network)}
                  </p>
                </li>
              </ul>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp format_port(host, container_port) do
    host_ip = value(host, "HostIp", :HostIp)
    host_port = value(host, "HostPort", :HostPort)
    "#{host_ip}:#{host_port}→#{container_port}"
  end

  defp format_network(name, network) do
    aliases = value(network, "Aliases", :Aliases) || ""
    dns_names = value(network, "DNSNames", :DNSNames) || ""
    "#{name} => {Aliases: #{inspect(aliases)}, DNS Names: #{inspect(dns_names)}}"
  end

  defp value(map, string_key, atom_key) do
    Map.get(map, string_key) || Map.get(map, atom_key)
  end
end
