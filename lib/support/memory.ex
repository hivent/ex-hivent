defmodule Hivent.Memory do
  @moduledoc """
  In-memory implementation of a Hivent emitter. Includes utility methods to query
  the cache. Use this in your tests to assert your events are properly published.
  """

  alias Hivent.{Event, Config}
  alias Event.Meta

  defmodule Emitter do
    @moduledoc false

    defmodule Cache do
      @moduledoc false
      use GenServer

      @name __MODULE__

      def start_link do
        GenServer.start_link(__MODULE__, :ok, [name: @name])
      end

      # API
      def insert(value) do
        GenServer.cast(@name, {:insert, value})
      end

      def all do
        GenServer.call(@name, {:all})
      end

      def last do
        GenServer.call(@name, {:last})
      end

      def clear do
        GenServer.cast(@name, {:clear})
      end

      def include?(payload, meta) do
        GenServer.call(@name, {:include?, payload, meta})
      end

      # Callbacks

      def init(:ok) do
        {:ok, []}
      end

      def handle_cast({:insert, value}, cache) do
        {:noreply, cache ++ [value]}
      end

      def handle_cast({:clear}, _cache) do
        {:noreply, []}
      end

      def handle_call({:last}, _from, cache) do
        {:reply, List.last(cache), cache}
      end

      def handle_call({:all}, _from, cache) do
        {:reply, cache, cache}
      end

      def handle_call({:include?, payload, meta}, _from, cache) do
        result = Enum.any?(cache, fn (event) ->
          match?(payload, event.payload) && Map.merge(event.meta, meta) == event.meta
        end)

        {:reply, result, cache}
      end
    end

    def emit(name, payload, %{version: version} = options, created_at \\ Timex.now) when is_integer(version) do
      build_message(name, payload, options[:cid], version, created_at)
      |> Poison.decode!(as: %Event{})
      |> Cache.insert
    end

    defp build_message(name, payload, cid, version, created_at) do
      %Event{
        payload: payload,
        meta:    meta_data(name, cid, version, created_at)
      } |> Poison.encode!
    end

    defp meta_data(name, cid, version, created_at) do
      %Meta{
        uuid:       UUID.uuid4(:hex),
        name:       name,
        version:    version || 1,
        cid:        cid || UUID.uuid4(:hex),
        producer:   Config.get(:hivent, :client_id),
        created_at: created_at |> DateTime.to_iso8601
      }
    end

  end

  @doc """
  Starts the Hivent.Memory server
  """
  def start(_type \\ nil, _args \\ nil) do
    {:ok, _} = Emitter.Cache.start_link
  end

  @doc """
  Emits an event to the memory store.
  """
  def emit(name, payload, options) do
    Emitter.emit(name, payload, options)
  end

  @doc """
  Gets all events currently in the memory store.
  """
  def all, do: Emitter.Cache.all

  @doc """
  Gets the last event emitted to the memory store.
  """
  def last, do: Emitter.Cache.last

  @doc """
  Clears the memory store.
  """
  def clear, do: Emitter.Cache.clear

  @doc """
  Checks if the memory store is empty.
  """
  def empty?, do: Enum.empty?(all)

  @moduledoc """
  Checks if an event with a given payload and/or metadata exists in the store.
  Supports partial matching for both payload and metadata.
  """
  def include?(payload, meta \\ %{}) do
    Emitter.Cache.include?(payload, meta)
  end
end
