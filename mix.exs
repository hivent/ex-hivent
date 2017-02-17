defmodule Hivent.Mixfile do
  use Mix.Project

  def project do
    [app: :hivent,
     version: "0.1.0",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [mod: {Hivent, []},
     applications: [:logger, :timex]]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      { :exredis, ">= 0.2.4" },
      { :uuid, "~> 1.1" },
      { :poison, "~> 2.0" },
      { :timex, "~> 3.0" },
      { :gen_stage, "~> 0.11" },
      { :credo, "~> 0.4", only: [:dev, :test] }
    ]
  end
end
