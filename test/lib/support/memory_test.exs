defmodule Hivent.MemoryTest do
  use ExUnit.Case

  setup do
    {:ok, _hivent} = Hivent.Memory.start

    Hivent.Memory.clear

    :ok
  end

  describe ".all" do
    test "it returns all events emitted" do
      Hivent.Memory.emit("an:event", %{foo: "bar"}, %{version: 1})
      Hivent.Memory.emit("another:event", %{foo: "bar"}, %{version: 1})

      events = Hivent.Memory.all

      event1 = List.first(events)
      event2 = List.last(events)

      assert length(events) == 2

      assert event1.meta.name == "an:event"
      assert event1.meta.version == 1
      assert event1.payload == %{"foo" => "bar"}

      assert event2.meta.name == "another:event"
      assert event2.meta.version == 1
      assert event2.payload == %{"foo" => "bar"}
    end
  end

  describe ".last" do
    test "it returns the last event emitted" do
      Hivent.Memory.emit("an:event", %{foo: "bar"}, %{version: 1})
      Hivent.Memory.emit("another:event", %{foo: "bar"}, %{version: 1})

      event = Hivent.Memory.last

      assert event.meta.name == "another:event"
      assert event.meta.version == 1
      assert event.payload == %{"foo" => "bar"}
    end
  end

  describe ".clear" do
    test "it clears the events from the memory cache" do
      Hivent.Memory.emit("an:event", %{foo: "bar"}, %{version: 1})
      Hivent.Memory.emit("another:event", %{foo: "bar"}, %{version: 1})

      Hivent.Memory.clear

      assert length(Hivent.Memory.all) == 0
    end
  end

  describe ".empty?" do
    test "it returns true when the cache is empty" do
      Hivent.Memory.clear

      assert Hivent.Memory.empty?
    end

    test "it returns false when the cache is not empty" do
      Hivent.Memory.emit("an:event", %{foo: "bar"}, %{version: 1})

      refute Hivent.Memory.empty?
    end
  end

  describe ".include?/2" do
    test "it returns true when the cache includes an event that matches the payload" do
      Hivent.Memory.emit("an:event", %{foo: "bar"}, %{version: 1})

      assert Hivent.Memory.include?(%{foo: "bar"})
    end

    test "it returns true when the cache includes an event that matches the payload and version" do
      Hivent.Memory.emit("an:event", %{foo: "bar"}, %{version: 2})

      refute Hivent.Memory.include?(%{foo: "bar"}, %{version: 1})
      assert Hivent.Memory.include?(%{foo: "bar"}, %{version: 2})
    end

    test "it returns true when the cache includes an event that matches the name" do
      Hivent.Memory.emit("an:event", %{foo: "bar"}, %{version: 2})

      assert Hivent.Memory.include?(%{}, %{name: "an:event"})
    end
  end
end
