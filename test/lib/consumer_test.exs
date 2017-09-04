defmodule Hivent.ConsumerTest do
  use ExUnit.Case, async: true
  import TimeHelper

  doctest Hivent.Consumer

  alias Hivent.{Config, Consumer, Event}

  @channel_client Application.get_env(:hivent, :channel_client)
  @reconnect_backoff_time Application.get_env(:hivent, :reconnect_backoff_time)
  @max_reconnect_tries Application.get_env(:hivent, :max_reconnect_tries)

  defmodule TestConsumer do
    @service "a_service"
    @topic "some:event"
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

    {:ok, hostname} = :inet.gethostname
    {:ok, pid} = TestConsumer.start_link()
    consumer_name = String.to_atom("consumer_socket_#{hostname}:#{inspect pid}")

    # Initial setup is async, so wait a bit for initial connect and join
    :timer.sleep(50)

    {:ok, %{consumer_name: consumer_name, pid: pid}}
  end

  test "connects to a socket with server config", %{consumer_name: consumer_name} do
    server_config = Config.get(:hivent, :hivent_server)
    socket_config = @channel_client.connected(consumer_name) |> hd

    assert socket_config.host == server_config[:host]
    assert socket_config.port == server_config[:port]
    assert socket_config.path == "/consumer/websocket"
    assert socket_config.secure == server_config[:secure]
  end

  test "connects to a socket with service name and consumer name", %{pid: pid, consumer_name: consumer_name} do
    socket_config = @channel_client.connected(consumer_name) |> hd

    {:ok, hostname} = :inet.gethostname

    assert socket_config.params.name == "#{hostname}:#{inspect pid}"
    assert socket_config.params.service == "a_service"
  end

  test "joins a channel on a topic named after the event with partition count", %{consumer_name: consumer_name} do
    channel_config = @channel_client.joined(consumer_name) |> hd

    assert channel_config.name == "event:some:event"
    assert channel_config.args.partition_count == 2
  end

  test "receives events", %{pid: pid} do
    event = %{
      "payload" => %{"response" => "ok"},
      "meta" => %{
        "name" => "some:event",
        "version" => 1
      }
    }

    decoded_event = Poison.encode!(event) |> Poison.decode!(as: %Hivent.Event{})

    send(pid, {"event:received", %{"event" => event, "queue" => "a_queue"}})

    assert_receive {:ok, ^decoded_event}
  end

  test "quarantines events that are not processed correctly", %{consumer_name: consumer_name, pid: pid} do
    event = %{
      "payload" => %{"response" => "error"},
      "meta" => %{
        "name" => "some:event",
        "version" => 1
      }
    }

    decoded_event = Poison.encode!(event) |> Poison.decode!(as: %Hivent.Event{})

    send(pid, {"event:received", %{"event" => event, "queue" => "a_queue"}})

    :timer.sleep(10)

    {quarantined_event, queue} = consumer_name
    |> @channel_client.quarantined
    |> hd

    assert quarantined_event == decoded_event
    assert queue == "a_queue"
  end

  test "reconnects to the socket with exponential backoff when the connection is closed", %{consumer_name: consumer_name} do
    reconnect_after = :erlang.round(@reconnect_backoff_time * :math.pow(2, @max_reconnect_tries - 2))

    @channel_client.crash(consumer_name, reconnect_after)

    wait_until fn ->
      assert (consumer_name |> @channel_client.connected |> length) > 0
    end
  end

  test "stops reconnecting to the socket after a maximum number of attempts have been reached", %{consumer_name: consumer_name, pid: pid} do
    Process.flag :trap_exit, true

    reconnect_after = :erlang.round(@reconnect_backoff_time * :math.pow(2, @max_reconnect_tries + 2))

    @channel_client.crash(consumer_name, reconnect_after)

    wait_until  fn ->
      assert_receive {:EXIT, ^pid, {:bad_return_value, {:error, "could not connect to socket"}}}
    end
  end
end
