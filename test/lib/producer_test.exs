defmodule HiventProducerTest do
  use ExUnit.Case
  use Timex
  doctest Hivent.Producer

  @signal "my_topic"
  @service_name "a_service"
  @version 1
  @cid "91dn1dn982d8921dasdads"

  setup do
    redis = Process.whereis(:redis)

    redis |> Exredis.Api.flushall

    partition_count = Hivent.Config.get(:hivent, :partition_count)

    redis |> Exredis.Api.sadd(@signal, @service_name)
    redis |> Exredis.Api.set("#{@service_name}:partition_count", partition_count)

    Hivent.Producer.emit(redis, @signal, "foobar",
      %{version: @version, cid: "91dn1dn982d8921dasdads", key: 12345}
    )

    item = redis
      |> Exredis.Api.lindex("#{@service_name}:0", -1)
      |> Poison.Parser.parse!(keys: :atoms)

    [redis: redis, item: item]
  end

  test "emitting an event creates an event with the given payload", %{item: item} do
    assert item.payload == "foobar"
  end

  test "emitting an event creates an event with the name of the used signal", %{item: item} do
    assert item.meta.name == @signal
  end

  test "emitting an event creates an event with the configured producer", %{item: item} do
    assert item.meta.producer == Hivent.Config.get(:hivent, :client_id)
  end

  test "emitting an event creates an event with the given version", %{item: item} do
    assert item.meta.version == @version
  end

  test "emitting an event creates an event with the given cid", %{item: item} do
    assert item.meta.cid == @cid
  end

  test "emitting an event creates an event with a generated uuid", %{item: item} do
    assert item.meta.uuid != nil
  end

  test "emitting an event creates an event with the date of emission", %{item: item} do
    created_at = Timex.parse!(item.meta.created_at, "{ISO:Extended:Z}")
    |> Timex.format("{YYYY}-{M}-{D} {h24}:{m}:{s}")

    assert created_at == Timex.now() |> Timex.format("{YYYY}-{M}-{D} {h24}:{m}:{s}")
  end
end
