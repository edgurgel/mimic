defmodule Mimic.Mixfile do
  use Mix.Project

  @source_url "https://github.com/edgurgel/mimic"
  @version "1.7.2"

  def project do
    [
      app: :mimic,
      version: @version,
      elixir: "~> 1.11",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      name: "Mimic",
      deps: deps(),
      package: package(),
      docs: docs(),
      test_coverage: [tool: Mimic.TestCover]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :tools],
      mod: {Mimic.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, "~> 1.0", only: :dev}
    ]
  end

  defp package do
    [
      description: "Mocks for Elixir functions",
      files: ["lib", "LICENSE", "mix.exs", "README.md"],
      licenses: ["Apache-2"],
      maintainers: ["Eduardo Gurgel"],
      links: %{
        "GitHub" => @source_url
      }
    ]
  end

  defp docs do
    [
      extras: [
        LICENSE: [title: "License"],
        "README.md": [title: "Overview"]
      ],
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      formatters: ["html"]
    ]
  end
end
