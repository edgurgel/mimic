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
# ** (Mimic.UnexpectedCallError) expected Calculator.add/2 to be called 0 time(s) but it has been called 1 time(s) in process #PID<0.281.0>
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
