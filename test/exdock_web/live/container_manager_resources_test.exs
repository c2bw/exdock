defmodule ExdockWeb.ContainerManagerResourcesTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Exdock.ReadModel.Container.Extended
  alias ExdockWeb.Commons.ContainerManager.Resources
  alias ExdockWeb.TestFixtures.Container, as: ContainerFixture

  test "renders all metrics from the latest resource sample" do
    container = ContainerFixture.read_model()

    resources = %{
      rates: %{
        cpu_usage: 12.5,
        used_memory: 512,
        io: %{read: 10, write: 20},
        net: %{rx: 30, tx: 40}
      },
      records: [
        %{
          cpu_count: 4,
          available_memory: 1_024,
          io: %{read: 100, write: 200},
          net: %{rx: 300, tx: 400}
        }
      ]
    }

    html =
      render_component(&Resources.render/1, %{
        core: container.core,
        extended: %Extended{resources: resources}
      })

    for label <- ["CPU", "Memory", "Disk read", "Disk write", "Network up", "Network down"] do
      assert html =~ label
    end
  end

  test "explains missing metrics for running and stopped containers" do
    running = ContainerFixture.read_model()
    stopped = ContainerFixture.read_model(is_running: false)

    running_html = render_component(&Resources.render/1, %{core: running.core, extended: running.extended})
    stopped_html = render_component(&Resources.render/1, %{core: stopped.core, extended: stopped.extended})

    assert running_html =~ "Waiting for the next sample"
    assert stopped_html =~ "Start the container to collect usage"
  end
end
