defmodule HiventEmitterTest do
  use ExUnit.Case
  use Timex
  doctest Hivent.Emitter

  @signal "my_topic"
  @service_name "a_service"
  @version 1
  @cid "91dn1dn982d8921dasdads"

  setup do
    redis = Process.whereis(Hivent.Redis)

    redis |> Exredis.Api.flushall

    partition_count = Hivent.Config.get(:hivent, :partition_count)

    created_at = Timex.now

    redis |> Exredis.Api.sadd(@signal, @service_name)
    redis |> Exredis.Api.set("#{@service_name}:partition_count", partition_count)

    Hivent.Emitter.emit(redis, @signal, "foobar",
      %{version: @version, cid: "91dn1dn982d8921dasdads", key: 12345},
      created_at
    )

    item = redis
      |> Exredis.Api.lindex("#{@service_name}:0", -1)
      |> Poison.Parser.parse!(keys: :atoms)

    [redis: redis, item: item, created_at: created_at]
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

  test "emitting an event creates an event with the date of emission", %{item: item, created_at: original_created_at} do
    created_at = Timex.parse!(item.meta.created_at, "{ISO:Extended:Z}")

    assert created_at == original_created_at
  end

  test "emitting an event with no key derives one from the payload", %{redis: redis} do
    redis |> Exredis.Api.set("#{@service_name}:partition_count", 2)

    # Is guaranteed to hit partition 2 when used with :erlang.crc32
    payload = %{foo: "bar"}

    Hivent.Emitter.emit(redis, @signal, payload,
      %{version: @version, cid: "91dn1dn982d8921dasdads"}
    )

    item = redis
      |> Exredis.Api.lindex("#{@service_name}:1", -1)

    assert item != :undefined
  end

  test "emitting an event with no cid generates one", %{redis: redis} do
    Exredis.Api.del(redis, "#{@service_name}:0")

    Hivent.Emitter.emit(redis, @signal, "foobar",
      %{version: @version}
    )

    item = redis
      |> Exredis.Api.lindex("#{@service_name}:0", -1)
      |> Poison.Parser.parse!(keys: :atoms)

    assert is_bitstring(item.meta.cid)
  end
end
