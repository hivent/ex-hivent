defmodule Hivent.Emitter do
  @moduledoc """
  The Hivent Emitter module. It emits signals into a Redis backend using a Lua script.
  """

  import Exredis.Script
  use Timex
  alias Hivent.Event
  alias Event.Meta

  defredis_script :produce, file_path: "lib/hivent/lua/producer.lua"

  def emit(redis, name, payload, options \\ %{cid: UUID.uuid4(:hex), version: 1, key: 1}) do
    message = build_message(name, payload, options[:cid], options[:version])

    redis
    |> produce([], [name, message, options[:key]])

    {:ok}
  end

  defp build_message(name, payload, cid, version) do
    %Event{
      payload: payload,
      meta:    meta_data(name, cid, version)
    }
    |> Poison.Encoder.encode([])
  end

  defp meta_data(name, cid, version) do
    %Meta{
      uuid:       UUID.uuid4(:hex),
      name:       name,
      version:    version,
      cid:        cid,
      producer:   Hivent.Config.get(:hivent, :client_id),
      created_at: Timex.now |> DateTime.to_iso8601
    }
  end
end