# 2.0.0 (2025-07-13)

## Breaking changes

The code below would call the original `Calculator.add/2` when all expectations were fulfilled.

```elixir
 Calculator
 |> expect(:add, fn _, _ -> :expected1 end)
 |> expect(:add, fn _, _ -> :expected2 end)

 assert Calculator.add(1, 1) == :expected1
 assert Calculator.add(1, 1) == :expected2
 assert Calculator.add(1, 1) == 2
```

Now with Mimic 2 this will raise:

```elixir
 Calculator
 |> expect(:add, fn _, _ -> :expected1 end)
 |> expect(:add, fn _, _ -> :expected2 end)

 assert Calculator.add(1, 1) == :expected1
 assert Calculator.add(1, 1) == :expected2
 Calculator.add(1, 1)
# Will raise error because more than 2 calls to Calculator.add were made and there is no stub
# ** (Mimic.UnexpectedCallError) Calculator.add/2 called in process #PID<.*> but expectations are already fulfilled
```

If there is a stub the stub will be called instead. This behaviour is the same as before.

```elixir
 Calculator
 |> expect(:add, fn _, _ -> :expected1 end)
 |> expect(:add, fn _, _ -> :expected2 end)
 |> stub(:add, fn _, _ -> :stub end)

 assert Calculator.add(1, 1) == :expected1
 assert Calculator.add(1, 1) == :expected2
 assert Calculator.add(1, 1) == :stub
```

Which means that if someone wants to keep the original behaviour on Mimic 1.* just do the following:

```elixir
 Calculator
 |> expect(:add, fn _, _ -> :expected1 end)
 |> expect(:add, fn _, _ -> :expected2 end)
 |> stub(:add, fn x, y -> call_original(Calculator, :add, [x, y]) end)

 assert Calculator.add(1, 1) == :expected1
 assert Calculator.add(1, 1) == :expected2
 assert Calculator.add(1, 1) == 2
```

This way once all expectations are fulfilled the original function is called again.
