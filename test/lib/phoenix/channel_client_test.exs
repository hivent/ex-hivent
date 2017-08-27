defmodule Hivent.Phoenix.ChannelClientTest do
  use ExUnit.Case

  alias Hivent.Phoenix.ChannelClient

  doctest ChannelClient

  @name :test
  @host "localhost"
  @path "/socket/websocket"
  @params %{authenticated: "true"}
  @port 9001
  @opts [
    host: @host,
    port: @port,
    path: @path,
    params: @params]

  setup_all do
    :ok
  end

  setup do
    on_exit fn ->
      if not is_nil(GenServer.whereis(@name)) do
        GenServer.stop(@name)
      end
    end
    ChannelClient.start(name: @name)
    :ok
  end

  test "connect successfully" do
    {:ok, _socket} = ChannelClient.connect(@name, @opts)
  end

  test "fail to connect" do
    params = %{
      authenticated: "false"
    }
    opts = [
      host: @host,
      port: @port,
      path: @path,
      params: params]
    assert ChannelClient.connect(@name, opts) == {:error, {403, "Forbidden"}}
  end

  test "join successfully" do
    {:ok, socket} = ChannelClient.connect(@name, @opts)
    channel = ChannelClient.channel(socket, "ok:topic", %{a: 1})
    assert ChannelClient.join(channel) == {:ok, %{"topic" => "topic", "params" => %{"a" => 1}}}
  end

  test "fail to join" do
    {:ok, socket} = ChannelClient.connect(@name, @opts)
    channel = ChannelClient.channel(socket, "error:topic", %{a: 1})
    assert ChannelClient.join(channel) == {:error, %{"topic" => "topic", "params" => %{"a" => 1}}}
  end

  test "push and receive ok" do
    {:ok, socket} = ChannelClient.connect(@name, @opts)
    channel = ChannelClient.channel(socket, "ok:topic", %{})
    ChannelClient.join(channel)
    assert ChannelClient.push_and_receive(channel, "reply_ok:event", %{a: 1}) ==
      {:ok, %{"event" => "event", "params" => %{"a" => 1}}}
  end

  test "push and receive error" do
    {:ok, socket} = ChannelClient.connect(@name, @opts)
    channel = ChannelClient.channel(socket, "ok:topic", %{})
    ChannelClient.join(channel)
    assert ChannelClient.push_and_receive(channel, "reply_error:event", %{a: 1}) ==
      {:error, %{"event" => "event", "params" => %{"a" => 1}}}
  end

  test "push" do
    {:ok, socket} = ChannelClient.connect(@name, @opts)
    channel = ChannelClient.channel(socket, "ok:topic", %{})
    ChannelClient.join(channel)
    assert ChannelClient.push(channel, "noreply:event", %{a: 1}) == :ok
  end

  test "push and ignore" do
    {:ok, socket} = ChannelClient.connect(@name, @opts)
    channel = ChannelClient.channel(socket, "ok:topic", %{})
    ChannelClient.join(channel)
    assert ChannelClient.push(channel, "reply_ok:event", %{a: 1}) == :ok
  end

  test "push and receive with noreply" do
    {:ok, socket} = ChannelClient.connect(@name, @opts)
    channel = ChannelClient.channel(socket, "ok:topic", %{})
    ChannelClient.join(channel)
    assert ChannelClient.push_and_receive(channel, "noreply:event", %{a: 1}, 20) == :timeout
  end

  test "leave" do
    {:ok, socket} = ChannelClient.connect(@name, @opts)
    channel = ChannelClient.channel(socket, "ok:topic", %{})
    ChannelClient.join(channel)
    assert ChannelClient.leave(channel) == {:ok, %{}}
  end

  test "unsubscribe properly" do
    {:ok, socket} = ChannelClient.connect(@name, @opts)
    channel1 = ChannelClient.channel(socket, "ok:1", %{})
    channel2 = ChannelClient.channel(socket, "ok:2", %{})
    ChannelClient.join(channel1)
    ChannelClient.join(channel2)
    assert Map.size(get_subscriptions()) == 2
    ChannelClient.push_and_receive(channel1, "reply_ok:event", %{a: 1})
    assert Map.size(get_subscriptions()) == 2
    ChannelClient.push(channel2, "noreply:event", %{a: 1})
    assert Map.size(get_subscriptions()) == 2
    ChannelClient.leave(channel1)
    ChannelClient.leave(channel2)
    assert Map.size(get_subscriptions()) == 0
  end

  test "timeout on join" do
    {:ok, socket} = ChannelClient.connect(@name, @opts)
    channel = ChannelClient.channel(socket, "sleep:1000", %{})
    assert ChannelClient.join(channel, 100) == :timeout
    assert Map.size(get_subscriptions()) == 0
  end

  test "timeout on push" do
    {:ok, socket} = ChannelClient.connect(@name, @opts)
    channel = ChannelClient.channel(socket, "ok:topic", %{})
    ChannelClient.join(channel, 100)
    assert Map.size(get_subscriptions()) == 1
    assert ChannelClient.push_and_receive(channel, "sleep:1000", %{a: 1}, 10) == :timeout
    assert Map.size(get_subscriptions()) == 1
  end

  test "receive messages" do
    {:ok, socket} = ChannelClient.connect(@name, @opts)
    channel = ChannelClient.channel(socket, "ok:topic", %{})
    ChannelClient.join(channel)
    ChannelClient.push(channel, "dispatch:ok:topic", %{event: "event", payload: %{a: 1}})
    assert Map.size(get_subscriptions()) == 1
    assert_receive {"event", %{"a" => 1}}
  end

  test "reconnect" do
    {:ok, socket} = ChannelClient.connect(@name, @opts)
    pid = get_recv_loop_pid()
    assert Process.alive?(pid)
    assert ChannelClient.reconnect(socket) == :ok
    refute Process.alive?(pid)
    pid = get_recv_loop_pid()
    assert Process.alive?(pid)
  end

  test "close properly" do
    {:ok, _socket} = ChannelClient.connect(@name, @opts)
    pid = get_recv_loop_pid()
    socket = get_socket()
    assert Process.alive?(pid)
    assert Port.info(socket.socket) != nil
    GenServer.stop(@name)
    refute Process.alive?(pid)
    refute Port.info(socket.socket) != nil
  end

  defp get_subscriptions, do: :sys.get_state(@name).subscriptions
  defp get_recv_loop_pid, do: :sys.get_state(@name).recv_loop_pid
  defp get_socket, do: :sys.get_state(@name).socket
end
