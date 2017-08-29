defmodule Hivent.ConsumerTest do
  use ExUnit.Case, async: true
  doctest Hivent.Consumer

  alias Hivent.{Config, Consumer, Event}

  @channel_client Application.get_env(:hivent, :channel_client)

  defmodule TestConsumer do
    @topic "some:event"
    @name "test_consumer"
    @partition_count 2

    @channel_client Application.get_env(:hivent, :channel_client)

    use Consumer

    def process(%Event{} = event) do
      case event.payload["response"] do
        "ok" ->
          send(:sut, {:ok, event})
          :ok
        "error" ->
          send(:sut, {:error, event})
          {:error, "something went wrong"}
      end
    end

    def handle_info(_, state), do: {:noreply, state}
  end

  setup do
    Process.register(self(), :sut)

    :ok
  end

  test "receives events" do
    {:ok, consumer} = TestConsumer.start_link()

    event = %Hivent.Event{
      payload: %{"response" => "ok"},
      meta: %Hivent.Event.Meta{
        name: "some:event",
        version: 1
      }
    }

    send(consumer, {"event:received", %{event: event, queue: "a_queue"}})

    assert_receive {:ok, ^event}
  end

  test "quarantines events that are not processed correctly" do
    {:ok, consumer} = TestConsumer.start_link()

    event = %Hivent.Event{
      payload: %{"response" => "error"},
      meta: %Hivent.Event.Meta{
        name: "some:event",
        version: 1
      }
    }

    send(consumer, {"event:received", %{event: event, queue: "a_queue"}})

    :timer.sleep(10)

    {quarantined_event, queue} = String.to_atom("consumer_socket_test_consumer")
    |> @channel_client.quarantined
    |> hd

    assert quarantined_event == event
    assert queue == "a_queue"
  end
end
