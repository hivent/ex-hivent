defmodule Hivent.Consumer.ProducerTest do
  use ExUnit.Case
  alias Experimental.GenStage

  doctest Hivent.Consumer.Producer

  @consumer "a_consumer"
  @events ["my:event"]
  @partition_count 2
  @interval 1000

  setup do
    {:ok, pid} = Hivent.Consumer.Producer.start_link(@consumer, @events, @partition_count, @interval)
    redis = Process.whereis(:redis)

    service = Hivent.Config.get(:hivent, :client_id)

    redis |> Exredis.Api.flushall

    redis |> Exredis.Api.set("#{service}:partition_count", @partition_count)

    redis |> Exredis.Api.sadd("my:event", service)

    Hivent.Heartbeat.start_link(@consumer, @interval)

    [pid: pid, redis: redis, service: service]
  end

  test "returns events when there is demand, if they exist", %{pid: producer} do
    Enum.each(1..@partition_count, fn (i) ->
      Hivent.emit("my:event", "foo (#{i})", %{key: Enum.random(1..10)})
    end)

    event_payloads = GenStage.stream([producer])
    |> Stream.map(fn (event) -> event.payload end)
    |> Enum.take(@partition_count)
    |> Enum.sort

    assert event_payloads == ["foo (1)", "foo (2)"]
  end

  test "consuming events removes them from Redis", %{pid: producer, redis: redis, service: service} do
    Enum.each(1..@partition_count, fn (i) ->
      Hivent.emit("my:event", "foo (#{i})", %{key: Enum.random(1..10)})
    end)

    GenStage.stream([producer]) |> Enum.take(2)

    queue_sizes = Enum.map(0..@partition_count-1, fn (i) ->
      redis |> Exredis.Api.llen("#{service}:#{i}") |> String.to_integer
    end)
    |> Enum.sum

    assert queue_sizes == 0
  end

  test "failing to parse an event puts it in the hospital queue", %{pid: producer, redis: redis, service: service} do
    redis |> Exredis.Api.lpush("#{service}:0", "invalid")
    Hivent.emit("my:event", "foo", %{key: Enum.random(1..10)})

    GenStage.stream([producer]) |> Enum.take(1)

    hospitalized_item = redis |> Exredis.Api.lindex("#{service}:0:dead_letter", 0)

    assert hospitalized_item == "invalid"
  end
end
