defmodule Hivent.Transports.MessagePackSerializer do
  @moduledoc false
  # https://nerds.stoiximan.gr/2016/11/23/binary-data-over-phoenix-sockets/

  alias Hivent.Event

  # only gzip data above 1K
  @gzip_threshold 1024

  def encode!(event) do
    event |> pack_data
  end

  def decode!(message, _opts) do
    unpack_data(message)
  end

  defp pack_data(data) do
    data
    |> Poison.encode!
    |> Poison.decode!
    |> Msgpax.pack!(enable_string: true)
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
