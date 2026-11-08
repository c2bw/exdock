defmodule Exdock.Domain.Container.ResourcesTest do
  use ExUnit.Case, async: true

  alias DockerEngineAPI.Model
  alias Exdock.Domain.Container.Resources
  alias Exdock.Domain.Container.Resources.Record.Parser

  test "record new/1 converts Docker stats into totals and CPU percentage" do
    assert %Resources.Record{} = record = Resources.Record.new(stats_response())

    assert record.time == ~U[2026-06-30 15:43:22Z]
    assert record.cpu_count == 4
    assert record.cpu_usage == 20.0
    assert record.used_memory == 87_281_664
    assert record.available_memory == 4_294_967_296
    assert record.io == %{read: 300, write: 75}
    assert record.net == %{rx: 1500, tx: 350}
  end

  test "record new/1 returns nil for invalid read timestamps" do
    assert Resources.Record.new(stats_response(read: "not-a-date")) == nil
  end

  test "record new/1 returns nil when CPU deltas cannot produce a rate" do
    assert Resources.Record.new(stats_response(system_cpu_usage: 4_000, precpu_system_cpu_usage: 4_000)) == nil
  end

  test "record new/1 ignores malformed IO and network rows" do
    record =
      Resources.Record.new(
        stats_response(
          io_entries: [%{"op" => "read", "value" => "bad"}, %{"op" => "flush", "value" => 50}],
          networks: %{"eth0" => %{"rx_bytes" => "bad", "tx_bytes" => 200}, "eth1" => %{}}
        )
      )

    assert record.io == %{read: 0, write: 0}
    assert record.net == %{rx: 0, tx: 0}
  end

  test "record new/1 treats optional IO and network stats as empty" do
    response =
      stats_response()
      |> Map.put("blkio_stats", nil)
      |> Map.put("networks", nil)

    assert %Resources.Record{io: %{read: 0, write: 0}, net: %{rx: 0, tx: 0}} =
             Resources.Record.new(response)
  end

  test "record new/1 totals wire-format block IO entries" do
    response =
      Map.put(stats_response(), "blkio_stats", %{
        "io_service_bytes_recursive" => [
          %{"op" => "read", "value" => 125},
          %{"op" => "write", "value" => 50}
        ]
      })

    assert %Resources.Record{io: %{read: 125, write: 50}} = Resources.Record.new(response)
  end

  test "record new/1 returns nil for missing required counters" do
    assert Resources.Record.new(Map.put(stats_response(), "memory_stats", nil)) == nil
    assert Resources.Record.new(Map.put(stats_response(), "cpu_stats", nil)) == nil
  end

  test "record parser preserves explicit validation errors" do
    assert Parser.parse(Map.put(stats_response(), "memory_stats", nil)) ==
             {:error, :invalid_memory_stats}

    assert Parser.parse(
             stats_response(
               system_cpu_usage: 4_000,
               precpu_system_cpu_usage: 4_000
             )
           ) == {:error, {:invalid_cpu_delta, 0}}
  end

  test "rates calculate/1 derives averages and per-second IO/network rates" do
    recent = record_at(~U[2026-06-30 15:43:24Z], 20.0, 200, %{read: 300, write: 100}, %{rx: 1000, tx: 500})
    older = record_at(~U[2026-06-30 15:43:22Z], 10.0, 100, %{read: 100, write: 50}, %{rx: 200, tx: 100})

    assert %Resources.Rates{
             cpu_usage: 15.0,
             used_memory: 150,
             io: %{read: 100, write: 25},
             net: %{rx: 400, tx: 200}
           } = Resources.Rates.calculate([recent, older])
  end

  test "drops the pre-reset window and resumes throughput with post-reset samples" do
    before_reset = record_at(~U[2026-06-30 15:43:20Z], 80.0, 900, %{read: 10000, write: 10000}, %{rx: 10000, tx: 10000})
    reset = record_at(~U[2026-06-30 15:43:22Z], 10.0, 100, %{read: 100, write: 100}, %{rx: 100, tx: 100})
    recent = record_at(~U[2026-06-30 15:43:24Z], 20.0, 200, %{read: 300, write: 200}, %{rx: 500, tx: 300})

    resources =
      Resources.new() |> Resources.add_record(before_reset, before_reset.time) |> Resources.add_record(reset, reset.time)

    assert resources.records == [reset]
    assert resources.rates.io == %{read: nil, write: nil}
    resources = Resources.add_record(resources, recent, recent.time)
    assert resources.records == [recent, reset]
    assert resources.rates.io == %{read: 100, write: 50}
    assert resources.rates.net == %{rx: 200, tx: 100}
    assert resources.rates.cpu_usage == 15.0
    assert Resources.Rates.calculate([recent, reset, before_reset]) == resources.rates
  end

  test "recognizes a reset in any cumulative counter even after totals recover" do
    before_reset = record_at(~U[2026-06-30 15:43:20Z], 80.0, 900, %{read: 100, write: 100}, %{rx: 100, tx: 100})

    for {field, key} <- [{:io, :read}, {:io, :write}, {:net, :rx}, {:net, :tx}] do
      reset = %{before_reset | time: ~U[2026-06-30 15:43:22Z]}
      reset = if field == :io, do: %{reset | io: Map.put(reset.io, key, 0)}, else: %{reset | net: Map.put(reset.net, key, 0)}
      recent = record_at(~U[2026-06-30 15:43:24Z], 20.0, 200, %{read: 200, write: 200}, %{rx: 200, tx: 200})
      assert Resources.Record.current_run([recent, reset, before_reset]) == [recent, reset]
    end
  end

  test "rates aggregate/2 returns totals only when the rate group is complete" do
    rates = %Resources.Rates{io: %{read: 100, write: 25}, net: %{rx: nil, tx: 200}}

    assert Resources.Rates.aggregate(rates, :io) == 125
    assert Resources.Rates.aggregate(rates, :net) == nil
  end

  test "rates calculate/1 keeps throughput at zero when records have no time gap" do
    time = ~U[2026-06-30 15:43:24Z]
    recent = record_at(time, 20.0, 200, %{read: 300, write: 100}, %{rx: 1000, tx: 500})
    older = record_at(time, 10.0, 100, %{read: 100, write: 50}, %{rx: 200, tx: 100})

    assert %Resources.Rates{
             cpu_usage: 15.0,
             used_memory: 150,
             io: %{read: 0, write: 0},
             net: %{rx: 0, tx: 0}
           } = Resources.Rates.calculate([recent, older])
  end

  test "add_record/3 stores the latest sample and recalculates rates" do
    now = DateTime.utc_now()
    older = record_at(DateTime.add(now, -2, :second), 10.0, 100, %{read: 100, write: 50}, %{rx: 200, tx: 100})
    recent = record_at(now, 20.0, 200, %{read: 300, write: 100}, %{rx: 1000, tx: 500})

    resources =
      Resources.new()
      |> Resources.add_record(older, now)
      |> Resources.add_record(recent, now)

    assert Resources.latest(resources) == recent
    assert resources.rates.cpu_usage == 15.0
    assert resources.rates.io == %{read: 100, write: 25}
  end

  test "telemetry structs are valid when constructed directly" do
    assert %Resources{rates: %Resources.Rates{}, records: []} = %Resources{}

    assert %Resources{} =
             %Exdock.Domain.Container.Extended{}
             |> Exdock.Domain.Container.Extended.add_record(nil, ~U[2026-07-31 10:00:00Z])
             |> Map.fetch!(:resources)
  end

  defp stats_response(overrides \\ []) do
    system_cpu_usage = Keyword.get(overrides, :system_cpu_usage, 5_000)
    precpu_system_cpu_usage = Keyword.get(overrides, :precpu_system_cpu_usage, 4_000)

    %Model.ContainerStatsResponse{
      read: Keyword.get(overrides, :read, "2026-06-30T15:43:22Z"),
      memory_stats: %Model.ContainerMemoryStats{usage: 87_281_664, limit: 4_294_967_296},
      cpu_stats: %Model.ContainerCpuStats{
        cpu_usage: %Model.ContainerCpuUsage{total_usage: 1_050},
        system_cpu_usage: system_cpu_usage,
        online_cpus: 4
      },
      precpu_stats: %Model.ContainerCpuStats{
        cpu_usage: %Model.ContainerCpuUsage{total_usage: 1_000},
        system_cpu_usage: precpu_system_cpu_usage
      },
      blkio_stats: %Model.ContainerBlkioStats{
        io_service_bytes_recursive:
          Keyword.get(overrides, :io_entries, [
            %{"op" => "read", "value" => 100},
            %{"op" => "read", "value" => 200},
            %{"op" => "write", "value" => 75}
          ])
      },
      networks:
        Keyword.get(overrides, :networks, %{
          "eth0" => %{"rx_bytes" => 1000, "tx_bytes" => 200},
          "eth1" => %{"rx_bytes" => 500, "tx_bytes" => 150}
        })
    }
    |> Exdock.Protocol.Value.encode()
  end

  defp record_at(time, cpu, memory, io, net) do
    %Resources.Record{
      time: time,
      cpu_count: 4,
      cpu_usage: cpu,
      used_memory: memory,
      available_memory: 1000,
      io: io,
      net: net
    }
  end
end
