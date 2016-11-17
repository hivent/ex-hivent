defmodule Hivent.Event do
  @moduledoc """
  Defines a Hivent Event struct.
  """
  defmodule Meta do
    @moduledoc false
    @enforce_keys [:name, :producer, :version, :cid, :uuid, :created_at]
    defstruct [:name, :producer, :version, :cid, :uuid, :created_at]
  end

  @enforce_keys [:meta, :payload]
  defstruct meta: Meta.__struct__, payload: %{}
end