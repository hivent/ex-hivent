defmodule Hivent.EmitterTest do
  use ExUnit.Case
  import TimeHelper

  doctest Hivent.Emitter

  @channel_client Application.get_env(:hivent, :channel_client)

  @reconnect_backoff_time Application.get_env(:hivent, :reconnect_backoff_time)
  @max_reconnect_tries Application.get_env(:hivent, :max_reconnect_tries)

  alias Hivent.{Config, Emitter}

  setup do
    @channel_client.reset(:emitter)

    server_config = Config.get(:hivent, :server)

    {:ok, pid} = Emitter.start_link([
      host: server_config[:host],
      port: server_config[:port],
      path: server_config[:path],
      secure: server_config[:secure],
      client_id: Config.get(:hivent, :client_id),
      api_key: server_config[:api_key]
    ])

    # First connect call is async
    :timer.sleep(25)

    {:ok, %{pid: pid}}
  end

  test "connects to the socket" do
    socket = @channel_client.connected(:emitter) |> hd

    server_config = Config.get(:hivent, :server)

    assert socket.host == server_config[:host]
    assert socket.port == server_config[:port]
    assert socket.path == server_config[:path]
    assert socket.secure == server_config[:secure]
    assert socket.params[:client_id] == Config.get(:hivent, :client_id)
    assert socket.params[:api_key] == server_config[:api_key]
  end

  test "joins the \"ingress:all\" channel" do
    channel = @channel_client.joined(:emitter) |> hd

    assert channel.name == "ingress:all"
  end

  test "emit/3 sends an event through the socket" do
    Emitter.emit("an:event", %{foo: "bar"}, %{version: 1, cid: "a_cid", key: "a_key"})

    :timer.sleep(10)

    event = @channel_client.messages(:emitter) |> hd

    assert event.name == "an:event"
    assert event.payload == %{foo: "bar"}
    assert event.meta.version == 1
    assert event.meta.cid == "a_cid"
    assert event.meta.key == "a_key"
    assert event.meta.producer == Config.get(:hivent, :client_id)
  end

  test "reconnects to the socket with exponential backoff when the connection is closed" do
    reconnect_after = :erlang.round(@reconnect_backoff_time * :math.pow(2, @max_reconnect_tries - 2))

    @channel_client.crash(:emitter, reconnect_after)

    wait_until fn ->
      assert (@channel_client.connected(:emitter) |> length) > 0
    end
  end

  test "stops reconnecting to the socket after a maximum number of attempts have been reached", %{pid: pid} do
    Process.flag :trap_exit, true

    reconnect_after = :erlang.round(@reconnect_backoff_time * :math.pow(2, @max_reconnect_tries + 2))

    @channel_client.crash(:emitter, reconnect_after)

    wait_until  fn ->
      assert_receive {:EXIT, ^pid, {:bad_return_value, {:error, "could not connect to socket"}}}
    end
  end
end
