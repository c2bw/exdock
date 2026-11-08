defmodule Exdock.ClientLib.Container.SnapshotMapperTest do
  use ExUnit.Case, async: true

  alias Exdock.ClientLib.Container.SnapshotMapper
  alias Exdock.Protocol.Snapshot.Container

  test "maps summary and inspect data to a protocol snapshot" do
    summary = summary(state: "running")

    inspect = %{
      :Image => "sha256:image",
      :Config => %{
        :Image => "example/app:latest",
        :Labels => %{"com.docker.compose.project" => "example"}
      }
    }

    assert %Container{
             name: "example-app",
             id: "container-id",
             is_running: true,
             stack_name: "example",
             image_tag: "example/app:latest",
             image_id: "sha256:image",
             inspect: ^inspect,
             resources: nil
           } = SnapshotMapper.from_inspect(summary, inspect)
  end

  test "handles inspect responses without labels" do
    inspect = %{
      :Image => "sha256:image",
      :Config => %{:Image => "example/app:latest", :Labels => nil}
    }

    assert %Container{stack_name: ""} = SnapshotMapper.from_inspect(summary(), inspect)
  end

  test "builds an identifiable fallback when inspect fails" do
    assert %Container{
             name: "example-app",
             id: "container-id",
             is_running: false,
             stack_name: nil,
             image_tag: nil,
             image_id: nil,
             inspect: nil,
             resources: nil
           } = SnapshotMapper.from_summary(summary())
  end

  defp summary(opts \\ []) do
    %{
      :Names => ["/example-app", "/example-alias"],
      :Id => "container-id",
      :State => Keyword.get(opts, :state, "exited")
    }
  end
end
