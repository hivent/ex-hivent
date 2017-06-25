defmodule HiventTest do
  use ExUnit.Case

  setup do
    redis = Process.whereis(Hivent.Redis)

    %{ redis: redis }
  end

  test "starts a persistent Redis connection", %{ redis: redis } do
    info = redis |> Exredis.Api.info(:server)

    assert info != ""
  end
end
