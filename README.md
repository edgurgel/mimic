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

If `:applications` key is defined inside your `mix.exs` or you run `mix test --no-start`, you probably want to add `Application.ensure_all_started(:mimic)` in your `test_helper.exs`

## Using

Modules need to be prepared so that they can be used.

You must first call `copy` in your `test_helper.exs` for
each module that may have the behaviour changed.

```elixir
Mimic.copy(Calculator)

ExUnit.start()
```

Calling `copy` will not change the behaviour of the module.

The user must call `stub/1`, `stub/3`, `expect/4` or `reject/1` so that the functions can
behave differently.

Then for the actual tests one could use it like this:

```elixir
use ExUnit.Case, async: true

import Mimic

# Make sure mocks are verified when the test exits
setup :verify_on_exit!

test "invokes add once and mult twice" do
  Calculator
  |> stub(:add, fn x, y -> :stub end)
  |> expect(:add, fn x, y -> x + y end)
  |> expect(:mult, 2, fn x, y -> x * y end)

  assert Calculator.add(2, 3) == 5
  assert Calculator.mult(2, 3) == 6
  assert Calculator.mult(4, 6) == 24

  assert Calculator.add(2, 3) == :stub
end
```

## Stub, Expect and Reject

### Stub

`stub/1` will change every module function to throw an exception if called.

```elixir
stub(Calculator)

** (Mimic.UnexpectedCallError) Stub! Unexpected call to Calculator.add(3, 7) from #PID<0.187.0>
     code: assert Calculator.add(3, 7) == 10
```

`stub/3` changes a specific function to behave differently. If the function is not called no verification error will happen.

### Expect

`expect/4` changes a specific function and it works like a queue of operations. It has precedence over stubs and if not called a verification error will be thrown.

If the same function is called with `expect/4` the order will be respected:

```elixir
Calculator
|> stub(:add, fn _x, _y -> :stub end)
|> expect(:add, fn _, _ -> :expected_1 end)
|> expect(:add, fn _, _ -> :expected_2 end)

assert Calculator.add(1, 1) == :expected_1
assert Calculator.add(1, 1) == :expected_2
assert Calculator.add(1, 1) == :stub
```

`expect/4` has an optional parameter which is the amount of calls expected:

```elixir
Calculator
|> expect(:add, fn x, y -> {:add, x, y} end)

assert Calculator.add(1, 3) == {:add, 1, 3}
assert Calculator.add(4, 5) == {:add, 4, 5}
```

### Reject

One may want to reject calls to a specific function. `reject/1` can be used to achieved this behaviour.

```elixir
reject(&Calculator.add/2)
assert_raise Mimic.UnexpectedCallError, fn -> Calculator.add(4, 2) end
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

## Implementation Details & Performance

After calling `Mimic.copy(MyModule)`, calls to functions belonging to this module will first go through an ETS table to check which pid sees what (stubs, expects or call original).

It is really fast but it won't be as fast as calling a no-op function. Here's a very simple benchmark:

```elixir
defmodule Enumerator do
 def to_list(x, y), do: Enum.to_list(x..y)
end
```

Benchmarking `Enumerator.to_list(1, 100)` :

```
Name               ips        average  deviation         median         99th %
mimic         116.00 K        8.62 μs   ±729.13%           5 μs          29 μs
original       19.55 K       51.15 μs   ±302.46%          34 μs         264 μs

Comparison:
mimic         116.00 K
original       19.55 K - 5.93x slower
```

Benchmarking `Enumerator.to_list(1, 250)` :

```
Name               ips        average  deviation         median         99th %
original      131.49 K        7.61 μs   ±167.90%           7 μs          16 μs
mimic         105.47 K        9.48 μs   ±145.21%           9 μs          27 μs

Comparison:
original      131.49 K
mimic         105.47 K - 1.25x slower
```

There's a small fixed price to pay when mimic is used but it is unnoticeable for tests purposes.
