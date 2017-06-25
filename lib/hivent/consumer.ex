defmodule Hivent.Consumer do
  use GenServer

  alias Hivent.Config
  alias Hivent.Consumer
  alias Hivent.Consumer.Stages.Producer, as: ProducerStage
  alias Hivent.Consumer.Stages.Consumer, as: ConsumerStage
  alias Phoenix.PubSub

  @callback process(%Hivent.Event{}) :: :ok | {:error, term}

  defmacro __using__(_options) do
    quote do
      @behaviour Consumer

      def start_link(otp_opts \\ []) do
        GenServer.start_link(__MODULE__, %{
          topic: @topic,
          name: @name,
          partition_count: @partition_count
        }, otp_opts)
      end

      def init(%{topic: topic, name: name, partition_count: partition_count}) do
        {:ok, producer} = case Process.whereis(Consumer.producer_name()) do
          nil -> ProducerStage.start_link(name, partition_count)
          pid -> pid
        end

        case Process.whereis(Consumer.consumer_name()) do
          nil -> ConsumerStage.start_link(producer)
        end

        Consumer.register(topic)

        :ok = PubSub.subscribe(:hivent_pubsub, topic)

        {:ok, %{topic: topic}}
      end

      def handle_info({event, queue}, state) do
        case process(event) do
          {:error, _reason} -> Consumer.hospitalize(event, queue)
          :ok -> nil
        end

        {:noreply, state}
      end

      def terminate(_reason, %{topic: topic}) do
        PubSub.unsubscribe(:hivent_pubsub, topic)
      end

      def process(_event), do: :ok
      defoverridable process: 1
    end
  end

  def register(topic) do
    redis() |> Exredis.Api.sadd(topic, service())
  end

  def hospitalize(event, queue) do
    redis() |> Exredis.Api.lpush("#{queue}:dead_letter", Poison.encode!(event))
  end

  def producer_name, do: String.to_atom("#{service()}_producer")

  def consumer_name, do: String.to_atom("#{service()}_consumer")

  defp redis, do: Process.whereis(:redis)

  defp service, do: Config.get(:hivent, :client_id)
end
