defmodule Hivent.EmitterTest do
  use ExUnit.Case

  doctest Hivent.Emitter

  @channel_client Application.get_env(:hivent, :channel_client)

  alias Hivent.{Config, Emitter}

  test "connects to the socket" do
    socket = @channel_client.connected(@channel_client) |> hd

    server_config = Config.get(:hivent, :hivent_server)

    assert socket.host == server_config[:host]
    assert socket.port == server_config[:port]
    assert socket.path == server_config[:path]
    assert socket.secure == server_config[:secure]
    assert socket.params[:client_id] == Config.get(:hivent, :client_id)
  end

  test "joins the \"ingress:all\" channel" do
    channel = @channel_client.joined(@channel_client) |> hd

    assert channel.name == "ingress:all"
  end

  test "emit/3 sends an event through the socket" do
    Emitter.emit("an:event", %{foo: "bar"}, %{version: 1, cid: "a_cid", key: "a_key"})

    :timer.sleep(10)

    event = @channel_client.messages(@channel_client) |> hd

    assert event.name == "an:event"
    assert event.payload == %{foo: "bar"}
    assert event.meta.version == 1
    assert event.meta.cid == "a_cid"
    assert event.meta.key == "a_key" |> :erlang.crc32
  end
end
