defmodule HiventProducerTest do
  use ExUnit.Case
  doctest Hivent.Producer

  @signal "my_topic"
  @service_name "a_service"

  setup do
    redis = Agent.get(Hivent, &Map.get(&1, :redis))

    redis |> Exredis.Api.flushall

    partition_count = Hivent.Config.get(:hivent, :partition_count)

    redis |> Exredis.Api.sadd(@signal, @service_name)
    redis |> Exredis.Api.set("#{@service_name}:partition_count", partition_count)

    [redis: redis]
  end

  test "emitting an event creates a list containing the message when a consuming service is configured", %{redis: redis} do
    Hivent.Producer.emit(redis, @signal, "foobar",
      %{version: 1, cid: "91dn1dn982d8921dasdads", key: 12345}
    )

    item = redis
      |> Exredis.Api.lindex("#{@service_name}:0", -1)
      |> Poison.Parser.parse!(keys: :atoms)

    assert item[:payload] == "foobar"
  end
end
