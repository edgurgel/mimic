defmodule Mack.Mixfile do
  use Mix.Project

  def project do
    [
      app: :mack,
      version: "0.1.0",
      elixir: "~> 1.3",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [applications: [:logger], mod: {Mack, []}]
  end

  defp deps do
    [{:ex2ms, "~> 1.0"}]
  end
end
