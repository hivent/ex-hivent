defmodule Hivent.ConsumerTest do
  use ExUnit.Case
  import TimeHelper

  defmodule TestConsumerSuccess do
    @topic "some:event"
    @name "test_consumer_success"
    @partition_count 2

    use Hivent.Consumer

    def process(event) do
      Agent.update(:success_events, fn (events) -> [event | events] end)
      :ok
    end
  end

  defmodule TestConsumerFailure do
    @topic "another:event"
    @name "test_consumer_failure"
    @partition_count 2

    use Hivent.Consumer

    def process(_event), do: {:error, "It's raaawww!"}
  end

  setup do
    redis = Process.whereis(Hivent.Redis)
    service = Hivent.Config.get(:hivent, :client_id)
    Agent.start_link(fn -> [] end, name: :success_events)

    [redis: redis, service: service]
  end

  test "initializing the consumer adds its service to the configured events consumer lists", %{redis: redis, service: service} do
    {:ok, _consumer} = TestConsumerSuccess.start_link()

    services = Exredis.Api.smembers(redis, "some:event")
    assert Enum.member?(services, service)
  end

  test "processes events that it registered for" do
    {:ok, _consumer} = TestConsumerSuccess.start_link()

    Hivent.emit("some:event", %{bar: "baz"}, %{version: 1, key: 0})

    wait_until 5_000, fn ->
      event = Agent.get(:success_events, fn (events) -> events end) |> hd
      assert event.meta.name == "some:event"
    end
  end

  test "when returning an error from the process() callback it puts the event in the dead letter queue", %{redis: redis, service: service} do
    {:ok, _consumer} = TestConsumerFailure.start_link()

    name = "another:event"
    payload = %{"foo" => "bar"}

    Hivent.emit(name, payload, %{version: 1, key: 0})

    wait_until 5_000, fn ->
      hospitalized_event = redis
        |> Exredis.Api.lindex("#{service}:0:dead_letter", 0)
        |> Poison.decode!(as: %Hivent.Event{})

      assert hospitalized_event.meta.name == name
      assert hospitalized_event.payload == payload
    end
  end

end
