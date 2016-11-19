defmodule HiventHeartbeatTest do
  use ExUnit.Case
  doctest Hivent.Heartbeat

  @consumer "a_consumer"
  @dead_consumer "dead_consumer"
  @interval 100

  setup do
    {:ok, pid} = Hivent.Heartbeat.start_link(@consumer, @interval)
    redis = Process.whereis(:redis)

    redis |> Exredis.Api.flushall

    service = Hivent.Config.get(:hivent, :client_id)

    [pid: pid, redis: redis, service: service]
  end

  test "keeps the consumer alive", %{redis: redis, service: service} do
    key = "#{service}:#{@consumer}:alive"

    round(@interval * 1.5) |> Process.sleep()

    alive = redis |> Exredis.Api.get(key)

    assert alive == "true"
  end

  test "cleans up dead consumers", %{redis: redis, service: service} do
    redis |> Exredis.Api.sadd("#{service}:consumers", @dead_consumer)

    round(@interval * 1.5) |> Process.sleep()

    consumers = redis |> Exredis.Api.smembers("#{service}:consumers")

    assert consumers == [@consumer]
  end
end
