# Mack

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add `mack` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:mack, "~> 0.1.0"}]
    end
    ```

  2. Ensure `mack` is started before your application:

    ```elixir
    def application do
      [applications: [:mack]]
    end
    ```


Usage:

```elixir
allow Math.sum(2, 3), fn x, y ->
  x * y
end

iex> Math.sum(1, 3)
6

allow Math.sum(_, 3), fn x, y ->
  5
end

iex> Math.sum(999, 3)
5
```
