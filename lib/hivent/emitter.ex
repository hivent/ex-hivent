defmodule Hivent.Emitter do
  @moduledoc """
  The Hivent Emitter module. It emits signals into a Hivent Server instance
  through a Websocket.
  """

  use GenServer
  alias Hivent.{Event, Config}
  alias Hivent.Phoenix.ChannelClient
  alias Event.Meta

  ## Client API
  def start_link([host: host, port: port, path: path, client_id: client_id]) do
    GenServer.start_link(__MODULE__, %{
      host: host,
      path: path,
      port: port,
      client_id: client_id
    }, name: __MODULE__)
  end

  def emit(server, name, payload, %{version: version} = options) when is_integer(version) do
    message = build_message(name, payload, options[:cid], version, options[:key])

    GenServer.cast(server, {:emit, message})

    {:ok}
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

  ## Server Callbacks
  def init(%{host: host, path: path, port: port, client_id: client_id}) do
    {:ok, pid} = ChannelClient.start_link

    {:ok, socket} = ChannelClient.connect(pid,
      host: host,
      path: path,
      port: port,
      params: %{client_id: client_id},
      secure: false
    )
    channel = ChannelClient.channel(socket, "ingress:all", %{})

    {:ok, _} = ChannelClient.join(channel)

    {:ok, %{socket: socket, channel: channel}}
  end

  def handle_cast({:emit, message}, %{channel: channel} = state) do
    ChannelClient.push_and_receive(channel, "event:emit", message)

    {:noreply, state}
  end

  def handle_info({_event, _payload}, state), do: {:noreply, state}
end
