defmodule Hivent.Phoenix.ChannelClient do
  @moduledoc """
  Phoenix Channels Client
  ### Example
  ```
  {:ok, pid} = ChannelClient.start_link()
  {:ok, socket} = ChannelClient.connect(pid,
    host: "localhost",
    path: "/socket/websocket",
    params: %{token: "something"},
    secure: false)
  channel = ChannelClient.channel(socket, "room:public", %{name: "Ryo"})
  case ChannelClient.join(channel) do
    {:ok, %{message: message}} -> IO.puts(message)
    {:error, %{reason: reason}} -> IO.puts(reason)
    :timeout -> IO.puts("timeout")
  end
  case ChannelClient.push_and_receive(channel, "search", %{query: "Elixir"}, 100) do
    {:ok, %{result: result}} -> IO.puts("#\{length(result)} items")
    {:error, %{reason: reason}} -> IO.puts(reason)
    :timeout -> IO.puts("timeout")
  end
  receive do
    {"new_msg", message} -> IO.puts(message)
    :close -> IO.puts("closed")
    {:error, error} -> ()
  end
  :ok = ChannelClient.leave(channel)
  ```
  """

  use GenServer

  defmodule Channel do
    defstruct [:socket, :topic, :params]
  end

  defmodule Socket do
    defstruct [:server_name]
  end

  defmodule Subscription do
    defstruct [:name, :pid, :matcher, :mapper]
  end

  alias Elixir.Socket.Web, as: WebSocket
  alias Hivent.Phoenix.Transports.MessagePackSerializer, as: Serializer

  @type channel :: %Channel{}
  @type socket :: %Socket{}
  @type subscription :: %Subscription{}

  @type ok_result :: {:ok, term}
  @type error_result :: {:error, term}
  @type timeout_result :: :timeout
  @type result :: ok_result | error_result | timeout_result
  @type send_result :: :ok | {:error, term}
  @type connect_error :: {:error, term}

  @default_timeout 5000
  @max_timeout 60000 # 1 minute

  @phoenix_vsn "1.0.0"

  @event_join "phx_join"
  @event_reply "phx_reply"
  @event_leave "phx_leave"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def start(opts \\ []) do
    GenServer.start(__MODULE__, :ok, opts)
  end

  @doc """
  Connects to the specified websocket.
  ### Options
  * `:host`
  * `:port` optional
  * `:path` optional, "/" by default
  * `:params` optional, %{} by default
  * `:secure` optional, false by default
  ### Example
  ```
  ChannelClient.connect(pid,
    host: "localhost",
    path: "/socket/websocket",
    params: %{token: "something"},
    secure: false)
  ```
  """
  @spec connect(term, keyword) :: {:ok, socket} | connect_error
  def connect(name, opts) do
    case GenServer.call(name, {:connect, opts}) do
      :ok -> {:ok, %Socket{server_name: name}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Reconnects to the socket.
  """
  @spec reconnect(socket) :: :ok | connect_error
  def reconnect(socket) do
    GenServer.call(socket.server_name, :reconnect)
  end

  @doc """
  Creates a channel struct.
  """
  @spec channel(socket, String.t, map) :: channel
  def channel(socket, topic, params \\ %{}) do
    %Channel{
      socket: socket,
      topic: topic,
      params: params
    }
  end

  @doc """
  Joins to the channel and subscribes messages.
  Receives `{event, payload}` or `:close`.
  ### Example
  ```
  case ChannelClient.join(channel) do
    {:ok, %{message: message}} -> IO.puts(message)
    {:error, %{reason: reason}} -> IO.puts(reason)
    :timeout -> IO.puts("timeout")
  end
  receive do
    {"new_msg", message} -> IO.puts(message)
    :close -> IO.puts("closed")
    {:error, error} -> ()
  end
  ```
  """
  @spec join(channel, number) :: result
  def join(channel, timeout \\ @default_timeout) do
    subscription = channel_subscription_key(channel)
    matcher = fn %{topic: topic} ->
      topic === channel.topic
    end
    mapper = fn %{event: event, payload: payload} -> {event, payload} end
    subscribe(channel.socket.server_name, subscription, matcher, mapper)
    case push_and_receive(channel, @event_join, channel.params, timeout) do
      :timeout ->
        unsubscribe(channel.socket.server_name, subscription)
        :timeout
      x -> x
    end
  end

  @doc """
  Leaves the channel.
  """
  @spec leave(channel, number) :: send_result
  def leave(channel, timeout \\ @default_timeout) do
    subscription = channel_subscription_key(channel)
    unsubscribe(channel.socket.server_name, subscription)
    push_and_receive(channel, @event_leave, %{}, timeout)
  end

  @doc """
  Pushes a message.
  ### Example
  ```
  case ChannelClient.push(channel, "new_msg", %{text: "Hello"}, 100) do
    :ok -> ()
    {:error, term} -> IO.puts("failed")
  end
  ```
  """
  @spec push(channel, String.t, map) :: send_result
  def push(channel, event, payload) do
    ref = GenServer.call(channel.socket.server_name, :make_ref)
    do_push(channel, event, payload, ref)
  end

  @doc """
  Pushes a message and receives a reply.
  ### Example
  ```
  case ChannelClient.push_and_receive(channel, "search", %{query: "Elixir"}, 100) do
    {:ok, %{result: result}} -> IO.puts("#\{length(result)} items")
    {:error, %{reason: reason}} -> IO.puts(reason)
    :timeout -> IO.puts("timeout")
  end
  ```
  """
  @spec push_and_receive(channel, String.t, map, number) :: result
  def push_and_receive(channel, event, payload, timeout \\ @default_timeout) do
    ref = GenServer.call(channel.socket.server_name, :make_ref)
    subscription = reply_subscription_key(ref)
    task = Task.async(fn ->
      matcher = fn %{topic: topic, event: event, ref: msg_ref} ->
        topic === channel.topic and event === @event_reply and msg_ref === ref
      end
      mapper = fn %{payload: payload} -> payload end
      subscribe(channel.socket.server_name, subscription, matcher, mapper)
      do_push(channel, event, payload, ref)
      receive do
        payload ->
          case payload do
            %{"status" => "ok", "response" => response} ->
              {:ok, response}
            %{"status" => "error", "response" => response} ->
              {:error, response}
          end
      after
        timeout -> :timeout
      end
    end)
    try do
      Task.await(task, @max_timeout)
    after
      unsubscribe(channel.socket.server_name, subscription)
    end
  end

  defp do_push(channel, event, payload, ref) do
    obj = %{
      topic: channel.topic,
      event: event,
      payload: payload,
      ref: ref
    }
    data = Serializer.encode!(obj)
    socket = GenServer.call(channel.socket.server_name, :socket)
    WebSocket.send!(socket, {:binary, data})
  end

  defp subscribe(name, key, matcher, mapper) do
    subscription = %Subscription{name: key, matcher: matcher, mapper: mapper, pid: self()}
    GenServer.cast(name, {:subscribe, subscription})
    subscription
  end

  defp unsubscribe(name, %Subscription{name: key}) do
    unsubscribe(name, key)
  end
  defp unsubscribe(name, key) do
    GenServer.cast(name, {:unsubscribe, key})
  end

  defp channel_subscription_key(channel), do: "channel_#{channel.topic}"
  defp reply_subscription_key(ref), do: "reply_#{ref}"

  defp do_connect(address, opts, state) do
    socket = state.socket
    if not is_nil(socket) do
      WebSocket.close(socket)
    end
    ensure_loop_killed(state)
    case WebSocket.connect(address, opts) do
      {:ok, socket} ->
        pid = spawn_recv_loop(socket)
        state = %{state |
          socket: socket,
          recv_loop_pid: pid}
        {:reply, :ok, state}
      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  @sleep_time_on_error 100
  defp spawn_recv_loop(socket) do
    pid = self()
    spawn_link(fn ->
      for _ <- Stream.cycle([:ok]) do
        case WebSocket.recv(socket) do
          {:ok, {:binary, data}} ->
            send pid, {:binary, data}
          {:ok, {:ping, _}} ->
            WebSocket.send!(socket, {:pong, ""})
          {:ok, {:close, _, _}} ->
            send pid, :close
          {:error, error} ->
            send pid, {:error, error}
            :timer.sleep(@sleep_time_on_error)
        end
      end
    end)
  end

  def ensure_loop_killed(state) do
    pid = state.recv_loop_pid
    if not is_nil(pid) do
      Process.unlink(pid)
      Process.exit(pid, :kill)
    end
  end

  # Callbacks

  def init(_opts) do
    initial_state = %{
      ref: 0,
      socket: nil,
      recv_loop_pid: nil,
      subscriptions: %{},
      connection_address: nil,
      connection_opts: nil
    }
    {:ok, initial_state}
  end

  def handle_call({:connect, opts}, _from, state) do
    {host, opts} = Keyword.pop(opts, :host)
    {port, opts} = Keyword.pop(opts, :port)
    {path, opts} = Keyword.pop(opts, :path, "/")
    {params, opts} = Keyword.pop(opts, :params, %{})
    params = Map.put(params, :vsn, @phoenix_vsn) |> URI.encode_query()
    path = "#{path}?#{params}"
    opts = Keyword.put(opts, :path, path)
    address = if not is_nil(port) do
      {host, port}
    else
      host
    end
    state = %{state |
      connection_address: address,
      connection_opts: opts}
    do_connect(address, opts, state)
  end

  def handle_call(:reconnect, _from, state) do
    %{
      connection_address: address,
      connection_opts: opts
    } = state
    do_connect(address, opts, state)
  end

  def handle_call(:make_ref, _from, state) do
    ref = state.ref
    state = Map.update!(state, :ref, &(&1 + 1))
    {:reply, ref, state}
  end

  def handle_call(:socket, _from, state) do
    {:reply, state.socket, state}
  end

  def handle_cast({:subscribe, subscription}, state) do
    state = put_in(state, [:subscriptions, subscription.name], subscription)
    {:noreply, state}
  end

  def handle_cast({:unsubscribe, key}, state) do
    state = Map.update!(state, :subscriptions, fn subscriptions ->
      Map.delete(subscriptions, key)
    end)
    {:noreply, state}
  end

  def handle_info({:binary, data}, state) do
    %{
      "event" => event,
      "topic" => topic,
      "payload" => payload
    } = decoded = Serializer.decode!(data)
    obj = %{
      event: event,
      topic: topic,
      payload: payload,
      ref: decoded["ref"]
    }
    filter = fn {_key, %Subscription{matcher: matcher}} ->
      matcher.(obj)
    end
    mapper = fn {_key, %Subscription{pid: pid, mapper: mapper}} ->
      {pid, mapper.(obj)}
    end
    sender = fn {pid, message} ->
      send pid, message
    end
    state.subscriptions
    |> Flow.from_enumerable()
    |> Flow.filter_map(filter, mapper)
    |> Flow.each(sender)
    |> Flow.run()
    {:noreply, state}
  end

  def handle_info(:close, state) do
    ensure_loop_killed(state)
    fn {pid, message} ->
      send pid, message
    end
    Enum.map(state.subscriptions, fn {_key, %Subscription{pid: pid}} ->
      spawn_link(fn ->
        send pid, :close
      end)
    end)
    {:noreply, state}
  end

  def handle_info({:error, error}, state) do
    Enum.map(state.subscriptions, fn {_key, %Subscription{pid: pid}} ->
      spawn_link(fn ->
        send pid, {:error, error}
      end)
    end)
    {:noreply, state}
  end

  def terminate(reason, state) do
    ensure_loop_killed(state)
    socket = state.socket
    if not is_nil(socket) do
      WebSocket.abort(socket)
    end
    reason
  end
end
