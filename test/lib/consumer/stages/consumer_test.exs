defmodule Hivent.Consumer.Stages.ConsumerTest do
  use ExUnit.Case

  doctest Hivent.Consumer.Stages.Consumer

  setup do
    service = Hivent.Config.get(:hivent, :client_id)
    consumer_name = "#{service}_consumer"

    redis = Process.whereis(Hivent.Redis)
    redis |> Exredis.Api.flushall
    redis |> Exredis.Api.set("#{service}:#{consumer_name}:alive", true)
    redis |> Exredis.Api.sadd("#{service}:consumers", consumer_name)
    redis |> Exredis.Api.sadd("my:event", service)

    {:ok, producer} = Hivent.Consumer.Stages.Producer.start_link(consumer_name, 2)
    {:ok, consumer} = Hivent.Consumer.Stages.Consumer.start_link(producer)

    Phoenix.PubSub.subscribe :hivent_pubsub, "my:event"

    [consumer: consumer]
  end

  test "broadcasts consumed events using a PubSub system" do
    Hivent.emit("my:event", "foo", %{version: 1, key: 1})

    assert_receive(_, 500)
  end
end
