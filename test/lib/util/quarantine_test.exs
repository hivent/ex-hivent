defmodule HiventQuarantineTest do
  use ExUnit.Case
  use Timex

  alias Hivent.{Event, Util}
  alias Event.Meta

  @signal "my_topic"
  @service_name "a_service"
  @queue "a_service:1"
  @item %Event{
    payload: %{
      "foo" => "bar"
    },
    meta: %Meta{
      name: "foo",
      producer: "bar_service",
      version: 1,
      cid: "91dn1dn982d8921dasdads",
      uuid: "f983nren873nf789829dn29",
      created_at: Timex.now |> Timex.format!("{ISO:Extended:Z}")
    }
  }

  setup do
    redis = Process.whereis(:redis)

    redis |> Exredis.Api.flushall

    partition_count = Hivent.Config.get(:hivent, :partition_count)

    redis |> Exredis.Api.sadd(@signal, @service_name)
    redis |> Exredis.Api.set("#{@service_name}:partition_count", partition_count)

    [redis: redis]
  end

  test "putting an event from a given queue in quarantine adds it to a dead letter queue", %{redis: redis} do
    {:ok} = Util.quarantine(redis, @item, @queue)

    quarantined_item = redis
      |> Exredis.Api.lindex("#{@service_name}:1:dead_letter", -1)
      |> Poison.decode!(as: %Event{})

    assert quarantined_item == @item
  end
end
