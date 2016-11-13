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
allow(Notification.should_pause?(1) -> false)
```
