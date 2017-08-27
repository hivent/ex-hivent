defmodule Hivent.Mixfile do
  use Mix.Project

  def project do
    [app: :hivent,
     version: "2.2.0",
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     description: description(),
     package: package(),
     deps: deps(),
     elixirc_paths: elixirc_paths(Mix.env)]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [mod: {Hivent, []},
     applications: [:logger]]
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
    [{:poison, "~> 3.1"},
     {:socket, "~> 0.3.11"},
     {:msgpax, "~> 2.0"},
     {:flow, "~> 0.12"},
     {:uuid, "~> 1.1"},
     {:timex, "~> 3.1"},
     {:credo, "~> 0.8", only: [:dev, :test]},
     {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
     {:test_server, path: "test/support/test_server", only: :test}]
  end

  defp description do
    """
    An event stream that aggregates facts about your application.
    """
  end

  defp package do
    [# These are the default files included in the package
     name: :hivent,
     maintainers: ["Bruno Abrantes"],
     licenses: ["MIT"],
     links: %{"GitHub" => "https://github.com/inf0rmer/ex-hivent",
              "Docs" => "https://github.com/inf0rmer/ex-hivent"}]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
