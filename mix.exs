defmodule Mimic.Mixfile do
  use Mix.Project

  def project do
    [
      app: :mimic,
      version: "0.1.0",
      elixir: "~> 1.6",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      name: "Mimic",
      description: "Mocks for Elixir functions",
      deps: deps(),
      package: package(),
      docs: [extras: ["README.md"], main: "readme"]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Mimic.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ex_doc, "~> 0.19", only: :dev},
      {:credo, "~> 0.10.0", only: :dev}
    ]
  end

  defp package do
    %{
      files: ["lib", "LICENSE", "mix.exs", "README.md"],
      licenses: ["Apache 2"],
      maintainers: ["Eduardo Gurgel"],
      links: %{"GitHub" => "https://github.com/edgurgel/mimic"}
    }
  end
end
