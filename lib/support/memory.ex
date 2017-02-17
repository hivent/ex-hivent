defmodule Hivent.Memory do
  alias Hivent.{Event, Config}
  alias Event.Meta

  defmodule Emitter do

    defmodule Cache do
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
    end

    def emit(name, payload, %{version: version} = options, created_at \\ Timex.now) when is_integer(version) do
      build_message(name, payload, options[:cid], version, created_at) |> Cache.insert
    end

    defp build_message(name, payload, cid, version, created_at) do
      %Event{
        payload: payload,
        meta:    meta_data(name, cid, version, created_at)
      }
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

  def start(_type, _args) do
    {:ok, _} = Emitter.Cache.start_link
  end

  def emit(name, payload, options) do
    Emitter.emit(name, payload, options)
  end
end
