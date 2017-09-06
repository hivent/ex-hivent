defmodule Hivent.Support.ChannelClient do
  use GenServer

  defmodule Channel do
    defstruct [:socket, :name, :args, :subscriber]
  end

  defmodule Socket do
    defstruct [:host, :path, :port, :params, :secure, :server]
  end

  # Client API
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, [], opts)
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
    GenServer.call(server, {:connect, socket})
  end

  def reconnect(socket) do
    GenServer.call(socket.server, {:connect, socket})
  end

  def channel(socket, name, args) do
    %Channel{socket: socket, name: name, args: args, subscriber: self()}
  end

  def join(%Channel{} = channel) do
    GenServer.call(channel.socket.server, {:join, channel})
  end

  def leave(%Channel{} = channel) do
    GenServer.call(channel.socket.server, {:leave, channel})
  end

  def push(channel, event, payload) do
    GenServer.cast(channel.socket.server, {:push, event, payload})
  end

  def messages(server) do
    GenServer.call(server, :messages)
  end

  def quarantined(server) do
    GenServer.call(server, :quarantined)
  end

  def connected(server) do
    GenServer.call(server, :connected)
  end

  def joined(server) do
    GenServer.call(server, :joined)
  end

  def reset(server) do
    GenServer.cast(server, :reset)
  end

  def crash(server, come_back_after \\ 10) do
    GenServer.cast(server, {:crash, come_back_after})
  end

  # Server API
  def init(_state) do
    {:ok, initial_state()}
  end

  def handle_cast({:push, "event:emit", event}, %{available: true} = state) do
    {:noreply, %{state | messages: state.messages ++ [event]}}
  end
  def handle_cast({:push, "event:emit", _}, %{available: false} = state) do
    {:noreply, state}
  end
  def handle_cast({:push, "event:quarantine", %{event: event, queue: queue}}, %{available: true} = state) do
    {:noreply, %{state | quarantined: state.quarantined ++ [{event, queue}]}}
  end
  def handle_cast({:push, "event:quarantine", _}, %{available: false} = state) do
    {:noreply, state}
  end
  def handle_cast(:reset, _state) do
    {:noreply, initial_state()}
  end
  def handle_cast({:crash, come_back_after}, %{joined: joined}) do
    Enum.each(joined, fn (%{subscriber: pid}) ->
      spawn_link fn -> send(pid, :close) end
    end)

    Process.send_after(self(), :reset, come_back_after)

    {:noreply, %{initial_state() | available: false}}
  end

  def handle_call({:connect, socket}, _from, %{available: true} = state) do
    {:reply, {:ok, socket}, %{state | connected: state.connected ++ [socket]}}
  end
  def handle_call({:connect, _}, _from, %{available: false} = state) do
    {:reply, {:error, "server is not available"}, state}
  end
  def handle_call({:join, channel}, _from, %{available: true} = state) do
    {:reply, {:ok, channel}, %{state | joined: state.joined ++ [channel]}}
  end
  def handle_call({:join, _}, _from, %{available: false} = state) do
    {:reply, {:error, "server is not available"}, state}
  end
  def handle_call({:leave, channel}, _from, state) do
    {:reply, :ok, %{state | joined: state.joined -- [channel]}}
  end
  def handle_call(:messages, _from, state) do
    {:reply, state.messages, state}
  end
  def handle_call(:quarantined, _from, state) do
    {:reply, state.quarantined, state}
  end
  def handle_call(:connected, _from, state) do
    {:reply, state.connected, state}
  end
  def handle_call(:joined, _from, state) do
    {:reply, state.joined, state}
  end

  def handle_info(:reset, state) do
    GenServer.cast(self(), :reset)

    {:noreply, state}
  end

  defp initial_state do
    %{connected: [], joined: [], messages: [], quarantined: [], available: true}
  end

end
