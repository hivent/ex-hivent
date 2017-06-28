# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :hivent,
  backend: :redis,
  endpoint: "redis://localhost:6379",
  partition_count: 4,
  client_id: "my_app"

config :logger,
  compile_time_purge_level: :info

env_config = Path.expand("#{Mix.env}.exs", __DIR__)
if File.exists?(env_config) do
  import_config(env_config)
end
