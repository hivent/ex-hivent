defmodule Hivent.Emitter do
  @moduledoc """
  The Hivent Emitter module. It emits signals into a Hivent Server instance
  through a Websocket.
  """

  use GenServer
  require Logger

  alias Hivent.{Config, Event}
  alias Event.Meta

  @typedoc "A Hivent Event struct"
  @type event :: %Event{}

  @typedoc "Return values of `start*` functions"
  @type on_start :: {:ok, pid} | :ignore | {:error, {:already_started, pid} | term}

  @channel_client Application.get_env(:hivent, :channel_client, Hivent.Phoenix.ChannelClient)
  @reconnect_backoff Application.get_env(:hivent, :reconnect_backoff_time, 1000)
  @max_reconnect_tries Application.get_env(:hivent, :max_reconnect_tries, 3)

  # Client API

  @doc """
  Starts the Emitter process. All options are required.
  ### Options
  * `:host`
  * `:port`
  * `:path`
  * `:secure`
  * `:client_id`
  * `:api_key`
  """
  @spec start_link(map) :: on_start
  def start_link([host: host, port: port, path: path, secure: secure, client_id: client_id, api_key: api_key]) do
    GenServer.start_link(__MODULE__, %{
      host: host,
      path: path,
      port: port,
      secure: secure,
      client_id: client_id,
      api_key: api_key,
      reconnect_timer: 0
    }, name: __MODULE__)
  end

  @doc """
  Emits the given event with name, payload and options
  ### Options
  * `:version`
  * `:cid` optional
  * `:key` optional, will be derived from `payload` by default. It controls which partition the event is stored in.
  ### Example
  ```
  Emitter.emit(
    "my:event",
    %{foo: "bar"},
    %{version: 1, cid: "a_correlation_id"}
  )
  ```
  """
  @spec emit(term, map, map) :: event
  def emit(name, payload, %{version: version} = options) when is_integer(version) do
    message = build_message(name, payload, options)

    GenServer.cast(__MODULE__, {:emit, message})

    {:ok, message}
  end

  defp build_message(name, payload, options) do
    %Event{
      name:    name,
      payload: payload,
      meta:    meta_data(options)
    }
  end

  defp meta_data(options) do
    %Meta{
      version:  options[:version],
      cid:      options[:cid],
      key:      options[:key],
      producer: Config.get(:hivent, :client_id)
    }
  end

  # Server Callbacks
  def init(config) do
    {:ok, pid} = @channel_client.start_link(name: :emitter)

    GenServer.cast(self(), :connect)

    {:ok, %{socket: nil, channel: nil, config: config, pid: pid, reconnect_tries: 0}}
  end

  def handle_cast({:emit, message}, %{channel: channel} = state) do
    @channel_client.push(channel, "event:emit", message)

    {:noreply, state}
  end
  def handle_cast(:connect, state), do: try_connect(state)

  def handle_info(:connect, state), do: try_connect(state)
  def handle_info(:close, state), do: try_connect(state)
  def handle_info(_, state), do: {:noreply, state}

  def terminate(_reason, %{channel: channel}) when not is_nil(channel) do
    @channel_client.leave(channel)
  end
  def terminate(_reason, _state), do: :ok

  defp try_connect(%{config: config} = state) do
    case do_connect(state) do
      {:ok, socket} ->
        channel = @channel_client.channel(socket, "ingress:all", %{})
        {:ok, _} = @channel_client.join(channel)

        {:noreply, %{state | socket: socket, channel: channel}}
      {:error, _reason} ->
        new_reconnect_timer = config[:reconnect_timer] + @reconnect_backoff

        cond do
          state[:reconnect_tries] <= @max_reconnect_tries ->
            Logger.info("Trying to reconnect to socket, #{@max_reconnect_tries - state[:reconnect_tries] + 1} tries left")
            Process.send_after(self(), :close, new_reconnect_timer)

            {:noreply, %{state |
              channel: nil,
              config: %{config |
                reconnect_timer: new_reconnect_timer,
              },
              reconnect_tries: state[:reconnect_tries] + 1
            }}
          true ->
            {:error, "could not connect to socket"}
        end
    end
  end

  defp do_connect(%{socket: nil, config: config, pid: pid}) do
    @channel_client.connect(pid,
      host: config[:host],
      path: config[:path],
      port: config[:port],
      params: %{
        client_id: config[:client_id],
        api_key:   config[:api_key]
      },
      secure: config[:secure]
    )
  end
  defp do_connect(%{socket: socket}) do
    case @channel_client.reconnect(socket) do
      :ok -> {:ok, socket}
      result -> result
    end
  end
end
