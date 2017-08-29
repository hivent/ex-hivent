defmodule Hivent.Emitter do
  @moduledoc """
  The Hivent Emitter module. It emits signals into a Hivent Server instance
  through a Websocket.

  {:ok, %Hivent.Event{}} = Hivent.Emitter.emit("my:event", %{foo: "bar", version: 1})
  """

  use GenServer
  alias Hivent.Event
  alias Event.Meta

  @type event :: %Event{}

  @channel_client Application.get_env(:hivent, :channel_client)

  # Client API
  def start_link([host: host, port: port, path: path, secure: secure, client_id: client_id]) do
    GenServer.start_link(__MODULE__, %{
      host: host,
      path: path,
      port: port,
      secure: secure,
      client_id: client_id
    }, name: __MODULE__)
  end

  @doc """
  Emits the given event with name, payload and options
  ### Options
  * `:version`
  * `:cid` optional
  * `:key` optional, "/" by default
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
    message = build_message(name, payload, options[:cid], version, options[:key])

    GenServer.cast(__MODULE__, {:emit, message})

    {:ok, message}
  end

  defp build_message(name, payload, cid, version, key) do
    key = (key || inspect(payload)) |> :erlang.crc32

    %Event{
      name: name,
      payload: payload,
      meta:    meta_data(cid, version, key)
    }
  end

  defp meta_data(cid, version, key) do
    %Meta{
      version: version,
      cid:     cid,
      key:     key
    }
  end

  # Server Callbacks
  def init(%{host: host, path: path, port: port, secure: secure, client_id: client_id}) do
    {:ok, pid} = @channel_client.start_link(name: :emitter)

    {:ok, socket} = @channel_client.connect(pid,
      host: host,
      path: path,
      port: port,
      params: %{client_id: client_id},
      secure: secure
    )
    channel = @channel_client.channel(socket, "ingress:all", %{})

    {:ok, _} = @channel_client.join(channel)

    {:ok, %{socket: socket, channel: channel}}
  end

  def handle_cast({:emit, message}, %{channel: channel} = state) do
    @channel_client.push(channel, "event:emit", message)

    {:noreply, state}
  end

  def handle_info({_event, _payload}, state), do: {:noreply, state}
end
