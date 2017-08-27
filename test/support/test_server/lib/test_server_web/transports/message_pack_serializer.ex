defmodule TestServerWeb.Transports.MessagePackSerializer do
  @moduledoc false
  # https://nerds.stoiximan.gr/2016/11/23/binary-data-over-phoenix-sockets/

  @behaviour Phoenix.Transports.Serializer

  alias Phoenix.Socket.Reply
  alias Phoenix.Socket.Message
  alias Phoenix.Socket.Broadcast

  # only gzip data above 1K
  @gzip_threshold 1024

  def fastlane!(%Broadcast{} = msg) do
    {:socket_push, :binary, pack_data(%{
      topic: msg.topic,
      event: msg.event,
      payload: msg.payload
    })}
  end

  def encode!(%Reply{} = reply) do
    packed = pack_data(%{
      topic: reply.topic,
      event: "phx_reply",
      ref: reply.ref,
      payload: %{
        status: reply.status,
        response: reply.payload
      }
    })

    {:socket_push, :binary, packed}
  end

  def encode!(%Message{} = msg) do
    data = Map.from_struct(msg) |> pack_data

    {:socket_push, :binary, data}
  end

  def decode!(message, _opts) do
    unpack_data(message)
    |> Phoenix.Socket.Message.from_map!()
  end

  defp pack_data(data) do
    Msgpax.pack!(data, enable_string: true)
    |> IO.iodata_to_binary
    |> gzip_data
  end

  defp unpack_data(data) do
    Msgpax.unpack!(data)
  end

  defp gzip_data(data), do: gzip_data(data, byte_size(data))
  defp gzip_data(data, size) when size < @gzip_threshold, do: data
  defp gzip_data(data, _size), do: :zlib.gzip(data)
end
