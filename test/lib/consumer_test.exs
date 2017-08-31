defmodule Hivent.ConsumerTest do
  use ExUnit.Case, async: true
  doctest Hivent.Consumer

  alias Hivent.{Config, Consumer, Event}

  @channel_client Application.get_env(:hivent, :channel_client)

  defmodule TestConsumer do
    @service "a_service"
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
  end

  setup do
    Process.register(self(), :sut)

    :ok
  end

  test "connects to a socket with server config" do
    {:ok, _consumer} = TestConsumer.start_link()
    channel_pid = String.to_atom("consumer_socket_test_consumer")
    server_config = Config.get(:hivent, :hivent_server)
    socket_config = @channel_client.connected(channel_pid) |> hd

    assert socket_config.host == server_config[:host]
    assert socket_config.port == server_config[:port]
    assert socket_config.path == "/consumer/websocket"
    assert socket_config.secure == server_config[:secure]
  end

  test "connects to a socket with service name and consumer name" do
    {:ok, _consumer} = TestConsumer.start_link()
    channel_pid = String.to_atom("consumer_socket_test_consumer")
    socket_config = @channel_client.connected(channel_pid) |> hd

    assert socket_config.params.name == "test_consumer"
    assert socket_config.params.service == "a_service"
  end

  test "joins a channel on a topic named after the event with partition count" do
    {:ok, _consumer} = TestConsumer.start_link()
    channel_pid = String.to_atom("consumer_socket_test_consumer")
    channel_config = @channel_client.joined(channel_pid) |> hd

    assert channel_config.name == "event:some:event"
    assert channel_config.args.partition_count == 2
  end

  test "receives events" do
    {:ok, consumer} = TestConsumer.start_link()

    event = %{
      "payload" => %{"response" => "ok"},
      "meta" => %{
        "name" => "some:event",
        "version" => 1
      }
    }

    decoded_event = Poison.encode!(event) |> Poison.decode!(as: %Hivent.Event{})

    send(consumer, {"event:received", %{"event" => event, "queue" => "a_queue"}})

    assert_receive {:ok, ^decoded_event}
  end

  test "quarantines events that are not processed correctly" do
    {:ok, consumer} = TestConsumer.start_link()

    event = %{
      "payload" => %{"response" => "error"},
      "meta" => %{
        "name" => "some:event",
        "version" => 1
      }
    }

    decoded_event = Poison.encode!(event) |> Poison.decode!(as: %Hivent.Event{})

    send(consumer, {"event:received", %{"event" => event, "queue" => "a_queue"}})

    :timer.sleep(10)

    {quarantined_event, queue} = String.to_atom("consumer_socket_test_consumer")
    |> @channel_client.quarantined
    |> hd

    assert quarantined_event == decoded_event
    assert queue == "a_queue"
  end
end
