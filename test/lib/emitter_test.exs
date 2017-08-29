defmodule Hivent.EmitterTest do
  use ExUnit.Case

  doctest Hivent.Emitter

  @channel_client Application.get_env(:hivent, :channel_client)

  alias Hivent.{Config, Emitter}

  setup do
    @channel_client.reset(:emitter)

    server_config = Config.get(:hivent, :hivent_server)

    {:ok, _pid} = Emitter.start_link([
      host: server_config[:host],
      port: server_config[:port],
      path: server_config[:path],
      secure: server_config[:secure],
      client_id: Config.get(:hivent, :client_id)
    ])

    :ok
  end

  test "connects to the socket" do
    socket = @channel_client.connected(:emitter) |> hd

    server_config = Config.get(:hivent, :hivent_server)

    assert socket.host == server_config[:host]
    assert socket.port == server_config[:port]
    assert socket.path == server_config[:path]
    assert socket.secure == server_config[:secure]
    assert socket.params[:client_id] == Config.get(:hivent, :client_id)
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
    assert event.meta.key == "a_key" |> :erlang.crc32
  end
end
