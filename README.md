# Hivent

## Emitting events
```elixir
Hivent.emit("some:event", %{foo: "bar"}, %{version: 1})
```

## Consuming events
```elixir
  defmodule TestConsumer do
    @topic "some:event"
    @name "test_consumer"
    @partition_count 2

    use Hivent.Consumer

    def process(%Hivent.Event{} = event) do
      if do_something(event) do
        :ok
      else
        # Puts the event in the dead letter queue
        {:error, "failed to process"}
      end
    end
  end
```

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

1. Add `hivent` to your list of dependencies in `mix.exs`:

 ```elixir
def deps do
  [{:hivent, "~> 2.0"}]
end
```

2. Ensure `hivent` is started before your application:

```elixir
def application do
  [applications: [:hivent]]
end
```
