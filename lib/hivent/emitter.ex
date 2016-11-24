defmodule Hivent.Emitter do
  @moduledoc """
  The Hivent Emitter module. It emits signals into a Redis backend using a Lua script.
  """

  import Exredis.Script
  use Timex
  alias Hivent.Event
  alias Event.Meta

  defredis_script :produce, file_path: "lib/hivent/lua/producer.lua"

  def emit(redis, name, payload, %{key: key} = options, created_at \\ Timex.now) do
    message = build_message(name, payload, options[:cid], options[:version], created_at)

    redis
    |> produce([], [name, message, key])

    {:ok}
  end

  defp build_message(name, payload, cid, version, created_at) do
    %Event{
      payload: payload,
      meta:    meta_data(name, cid, version, created_at)
    }
    |> Poison.Encoder.encode([])
  end

  defp meta_data(name, cid, version, created_at) do
    %Meta{
      uuid:       UUID.uuid4(:hex),
      name:       name,
      version:    version || 1,
      cid:        cid || UUID.uuid4(:hex),
      producer:   Hivent.Config.get(:hivent, :client_id),
      created_at: created_at |> DateTime.to_iso8601
    }
  end
end
