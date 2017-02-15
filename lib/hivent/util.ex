defmodule Hivent.Util do

  alias Hivent.Event

  def quarantine(redis, %Event{} = item, queue) do
    redis |> Exredis.Api.lpush("#{queue}:dead_letter", Poison.encode!(item))

    {:ok}
  end

end
