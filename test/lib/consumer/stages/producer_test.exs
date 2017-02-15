defmodule Hivent.Consumer.Stages.ProducerTest do
  use ExUnit.Case
  alias Experimental.GenStage

  doctest Hivent.Consumer.Stages.Producer

  @consumer "a_consumer"
  @events ["my:event"]
  @partition_count 2
  @interval 10_000

  setup do
    service = Hivent.Config.get(:hivent, :client_id)
    redis = Process.whereis(:redis)
    redis |> Exredis.Api.flushall

    redis |> Exredis.Api.set("#{service}:#{@consumer}:alive", true)
    redis |> Exredis.Api.sadd("#{service}:consumers", @consumer)

    {:ok, pid} = Hivent.Consumer.Stages.Producer.start_link(@consumer, @events, @partition_count, @interval)

    [pid: pid, redis: redis, service: service]
  end

  test "initializing the consumer sets its partition_count in Redis", %{redis: redis, service: service} do
    partition_count = redis
    |> Exredis.Api.get("#{service}:partition_count")
    |> String.to_integer

    assert partition_count == @partition_count
  end

  test "initializing the consumer adds its service to the configured events consumer lists", %{redis: redis, service: service} do
    assert @events
    |> Enum.all?(fn (event) ->
      services = Exredis.Api.smembers(redis, event)
      Enum.member?(services, service)
    end)
  end

  test "returns events when there is demand, if they exist", %{pid: producer} do
    Enum.each(1..@partition_count, fn (i) ->
      Hivent.emit("my:event", "foo (#{i})", %{version: 1, key: Enum.random(1..10)})
    end)

    event_payloads = GenStage.stream([producer])
    |> Stream.map(fn ({event, _queue}) -> event.payload end)
    |> Enum.take(@partition_count)
    |> Enum.sort

    assert event_payloads == ["foo (1)", "foo (2)"]
  end

  test "returns the queue for each event when there is demand, if events exist", %{pid: producer} do
    Enum.each(1..@partition_count, fn (i) ->
      Hivent.emit("my:event", "foo (#{i})", %{version: 1, key: i})
    end)

    service = Hivent.Config.get(:hivent, :client_id)

    event_queues = GenStage.stream([producer])
    |> Stream.map(fn ({_event, queue}) -> queue end)
    |> Enum.take(@partition_count)
    |> Enum.sort

    assert event_queues == ["#{service}:0", "#{service}:1"]
  end

  test "consuming events removes them from Redis", %{pid: producer, redis: redis, service: service} do
    Enum.each(1..@partition_count, fn (i) ->
      Hivent.emit("my:event", "foo (#{i})", %{version: 1, key: Enum.random(1..10)})
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
    Hivent.emit("my:event", "foo", %{version: 1, key: Enum.random(1..10)})

    GenStage.stream([producer]) |> Enum.take(1)

    hospitalized_item = redis |> Exredis.Api.lindex("#{service}:0:dead_letter", 0)

    assert hospitalized_item == "invalid"
  end
end
