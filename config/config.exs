# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :hivent,
  backend: :redis,

  endpoint: "redis://localhost:6379",

  partition_count: 4,

  client_id: "my_app"

import_config "#{Mix.env}.exs"
