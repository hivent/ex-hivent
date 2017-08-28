defmodule Hivent.Support.ChannelClient do
  use GenServer

  defmodule Channel do
    defstruct [:socket, :name, :args]
  end

  defmodule Socket do
    defstruct [:host, :path, :port, :params, :secure, :server]
  end

  # Client API
  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def connect(server, options) do
    socket = %Socket{
      host: options[:host],
      path: options[:path],
      port: options[:port],
      params: options[:params],
      secure: options[:secure],
      server: server
    }
    GenServer.cast(server, {:connect, socket})

    {:ok, socket}
  end

  def channel(socket, name, args) do
    %Channel{socket: socket, name: name, args: args}
  end

  def join(%Channel{} = channel) do
    GenServer.cast(channel.socket.server, {:join, channel})

    {:ok, channel}
  end

  def push(channel, event, payload) do
    GenServer.cast(channel.socket.server, {:emit, event, payload})
  end

  def messages(server) do
    GenServer.call(server, :messages)
  end

  def connected(server) do
    GenServer.call(server, :connected)
  end

  def joined(server) do
    GenServer.call(server, :joined)
  end

  # Server API
  def init(_state) do
    {:ok, %{connected: [], joined: [], messages: []}}
  end

  def handle_cast({:connect, socket}, state) do
    {:noreply, %{state | connected: state.connected ++ [socket]}}
  end
  def handle_cast({:join, channel}, state) do
    {:noreply, %{state | joined: state.joined ++ [channel]}}
  end
  def handle_cast({:emit, "event:emit", event}, state) do
    {:noreply, %{state | messages: state.messages ++ [event]}}
  end

  def handle_call(:messages, _from, state) do
    {:reply, state.messages, state}
  end
  def handle_call(:connected, _from, state) do
    {:reply, state.connected, state}
  end
  def handle_call(:joined, _from, state) do
    {:reply, state.joined, state}
  end

end
