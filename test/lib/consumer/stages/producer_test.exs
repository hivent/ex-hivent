defmodule Hivent.Consumer.Stages.ProducerTest do
  use ExUnit.Case

  doctest Hivent.Consumer.Stages.Producer

  @consumer_name "a_consumer"
  @partition_count 2
  @interval 25

  setup do
    service = Hivent.Config.get(:hivent, :client_id)
    redis = Process.whereis(:redis)
    redis |> Exredis.Api.flushall

    redis |> Exredis.Api.set("#{service}:#{@consumer_name}:alive", true)
    redis |> Exredis.Api.sadd("#{service}:consumers", @consumer_name)
    redis |> Exredis.Api.sadd("my:event", Hivent.Config.get(:hivent, :client_id))

    {:ok, pid} = Hivent.Consumer.Stages.Producer.start_link(@consumer_name, @partition_count, @interval)

    [pid: pid, redis: redis, service: service]
  end

  test "initializing the consumer sets its partition_count in Redis", %{redis: redis, service: service} do
    partition_count = redis
    |> Exredis.Api.get("#{service}:partition_count")
    |> String.to_integer

    assert partition_count == @partition_count
  end

  test "returns the queue for each event when there is demand, if events exist", %{pid: producer} do
    Enum.each(1..@partition_count, fn (i) ->
      Hivent.emit("my:event", "foo (#{i})", %{version: 1, key: i})
      :timer.sleep(25)
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
      :timer.sleep(25)
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
