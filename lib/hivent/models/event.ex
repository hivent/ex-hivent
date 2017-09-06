defmodule Hivent.Event do
  @moduledoc """
  A Hivent Event struct.
  * `payload` contains the actual content of the event
  * `meta` contains supporting metadata, such as date of creation, name of producer, etc.

  ### Example
  ```
  %Hivent.Event{
    payload: %{
      "item" => 55,
      "quantity" => 10
    },
    meta: %Hivent.Event.Meta{
      created_at: <date of creation, formatted as ISO8601>
      name: "order:confirmed",
      version: 1,
      producer: "order_service",
      uuid: "3c98bb60-5658-4fea-93d7-46c00c8d9b11",
      key: "f85977a0-8f69-459f-a2a0-4aff62ff6692"
    }
  }
  ```
  """
  @derive [Poison.Encoder]

  defmodule Meta do
    @moduledoc false
    @derive [Poison.Encoder]
    defstruct [:name, :producer, :version, :cid, :uuid, :created_at, :key]
  end

  defstruct meta: Meta.__struct__, payload: %{}, name: nil
end
