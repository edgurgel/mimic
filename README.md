# Mimic

A sane way of using mocks in Elixir. It borrows a lot from both Meck & Mox! Thanks @eproxus & @josevalim

## Installation

Just add mimic to your list of dependencies in mix.exs:

```elixir
def deps do
  [
    {:mimic, "~> 0.1", only: :test}
  ]
end
```

If `:applications` key is defined inside your `mix.exs`, you probably want to start with `Application.ensure_all_started(:mimic)` in your `test_helper.exs`

## Using

Modules need to be prepared so that they can be used.

You must first call `copy` in your `test_helper.exs` for
each module that may have the behaviour changed.

```elixir
Mimic.copy(Calculator)

ExUnit.start()
```

Calling `copy` will not change the behaviour of the module.

The user must call `stub/1`, `stub/3` or `expect/3` so that the functions will
behave differently.

Then for the actual tests one would use it like this:

```elixir
use ExUnit.Case, async: true

import Mimic

# Make sure mocks are verified when the test exits
setup :verify_on_exit!

test "invokes add and mult" do
  Calculator
  |> stub(:add, fn x, y -> :stub end)
  |> expect(:add, fn x, y -> x + y end)
  |> expect(:mult, fn x, y -> x * y end)

  assert Calculator.add(2, 3) == 5
  assert Calculator.mult(2, 3) == 6
end
```

## Stub and Expect

### Stub

`stub/1` will change every module function to throw an exception if called.

```elixir
stub(Calculator)

** (Mimic.UnexpectedCallError) Stub! Unexpected call to Calculator.add(3, 7) from #PID<0.187.0>
     code: assert Calculator.add(3, 7) == 10
```

`stub/3` changes a specific function to behave differently. If the function is not called no verification error will happen.


### Expect

`expect/3` changes a specific function and it works like a queue of operations. It has precedence over stubs.

If the same function is called with `expect/3` the order will be respected:

```elixir
Calculator
|> stub(:add, fn _x, _y -> :stub end)
|> expect(:add, fn _, _ -> :expected_1 end)
|> expect(:add, fn _, _ -> :expected_2 end)

assert Calculator.add(1, 1) == :expected_1
assert Calculator.add(1, 1) == :expected_2
assert Calculator.add(1, 1) == :stub
```

## Private and Global mode

The default mode is private which means that only the process
and explicitly allowed process will see the different behaviour.

Calling `allow/2` will permit a different pid to call the stubs and expects from the original process.

Global mode can be used with `set_mimic_global` like this:

```
setup :set_mimic_global

test "invokes add and mult" do
  Calculator
  |> expect(:add, fn x, y -> x + y end)
  |> expect(:mult, fn x, y -> x * y end)

  Task.async(fn ->
    assert Calculator.add(2, 3) == 5
    assert Calculator.mult(2, 3) == 6
  end)
  |> Task.await
end
```

This means that all processes will get the same behaviour
defined with expect & stub. This option is simpler but tests running
concurrently will have undefined behaviour. It is important to run with `async: false`.
One could use `:set_mimic_from_context` instead of using `:set_mimic_global` or `:set_mimic_private`. It will be private if `async: true`, global otherwise.
