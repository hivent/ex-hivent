defmodule Hivent.Emitter do
  @moduledoc """
  The Hivent Emitter module. It emits signals into a Hivent Server instance
  through a Websocket.
  """

  use GenServer
  alias Hivent.{Event, Config}
  alias Hivent.Emitter.Socket
  alias Event.Meta

  ## Client API
  def start_link([url: url, client_id: client_id]) do
    GenServer.start_link(__MODULE__, %{url: url, client_id: client_id}, name: __MODULE__)
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
  def init(%{url: url, client_id: client_id}) do
    {:ok, socket} = Socket.start_link(self, "#{url}?client_id=#{client_id}")
    Socket.join(socket, "ingress:all", %{})

    {:ok, %{socket: socket}}
  end

  def handle_cast({:emit, message}, %{socket: socket} = state) do
    Socket.send_event(socket, "ingress:all", "event:emit", message)

    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
