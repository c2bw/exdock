defmodule ExdockWeb.ContainerManagerPresentationTest do
  use ExUnit.Case, async: true

  alias ExdockWeb.Commons.ContainerManager.Presentation
  alias ExdockWeb.TestFixtures.Container, as: ContainerFixture

  test "builds status, notice, and digest presentation once" do
    core = core_fixture()
    presentation = Presentation.build("api", core, core.fetched_at)

    assert [{:running, _duration, _color}, {:updated, _date}] = presentation.status_messages
    assert presentation.local_digest == core.image_data.image.digest
    refute presentation.show_remote_digest?
  end

  test "exposes remote image state for outdated containers" do
    core = core_fixture()
    core = %{core | image_data: %{core.image_data | status: :outdated, present_on_node: false}}

    presentation = Presentation.build("api", core, core.fetched_at)

    assert Enum.any?(presentation.status_messages, &match?({:outdated, _, _, _}, &1))
    assert {:image_present, false} in presentation.status_messages
    assert presentation.show_remote_digest?
  end

  test "warns when recreation is disabled by name or protection label" do
    core = core_fixture()
    assert :recreate_disabled in Presentation.build("exdock-server-1", core, core.fetched_at).info_messages
    configuration = Map.put(core.configuration, :labels, %{"exdock.protected" => "true"})
    core = %{core | configuration: configuration}
    assert :recreate_disabled in Presentation.build("server", core, core.fetched_at).info_messages
  end

  defp core_fixture do
    core = ContainerFixture.read_model().core
    now = core.fetched_at

    image_data = %{
      status: :updated,
      present_on_node: true,
      image: %{digest: "sha256:local", build_date: now},
      tag_info: %{latest_digest: "sha256:remote", latest_date: now}
    }

    %{core | image_data: image_data}
  end
end
