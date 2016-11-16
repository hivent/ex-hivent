defmodule Hivent do
  @moduledoc """
  The main Hivent module.
  """

  import Exredis.Script

  defredis_script :produce, file_path: "lib/hivent/lua/producer.lua"

  def emit(name, payload, options \\ %{cid: UUID.uuid4(:hex), version: 1, key: 1}) do
    message = build_message(name, payload, options[:cid], options[:version])

    redis |> produce([], [name, message, options[:key]])

    {:ok}
  end

  defp redis do
    Exredis.start_using_connection_string Hivent.Config.get(:hivent, :endpoint)
  end

  defp build_message(name, payload, cid, version) do
    %{
      payload: payload,
      meta:    meta_data(name, cid, version)
    } |> Poison.Encoder.encode([])
  end

  defp meta_data(name, cid, version) do
    %{
      uuid:       UUID.uuid4(:hex),
      name:       name,
      version:    version,
      cid:        cid,
      producer:   Hivent.Config.get(:hivent, :client_id),
      created_at: DateTime.utc_now() |> DateTime.to_iso8601
    }
  end
end
